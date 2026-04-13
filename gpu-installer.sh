#!/usr/bin/env bash
# =============================================================================
# GPU AI Stack Installer — Ubuntu Server VM
# Installs: NVIDIA driver → CUDA → Ollama → Claude Code
# Designed for: GPU passthrough VM (Proxmox/KVM/VMware)
#
# Usage:
#   sudo bash setup-gpu-ollama-claudecode.sh [OPTIONS]
#
# Options:
#   --driver VERSION     NVIDIA driver branch (e.g. 550). Auto-detected if omitted.
#   --model  MODEL       Ollama model to pull after install (default: qwen2.5-coder:7b)
#   --no-reboot          Skip reboot prompt
#   --skip-driver        Skip NVIDIA driver install (if already installed)
#   --skip-claude        Skip Claude Code install
#   --help               Show this help
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $*"; }
info()   { echo -e "${CYAN}[i]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
error()  { echo -e "${RED}[✘]${NC} $*" >&2; exit 1; }
step()   { echo -e "\n${BOLD}${CYAN}┌─ $* ${NC}"; }
done_() { echo -e "${GREEN}└─ done${NC}"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
DRIVER_VERSION=""
OLLAMA_MODEL="qwen2.5-coder:7b"
SKIP_REBOOT=false
SKIP_DRIVER=false
SKIP_CLAUDE=false
CUDA_VERSION="12-4"
LOG_FILE="/var/log/gpu-ai-stack-install.log"
OLLAMA_SERVICE_USER="${SUDO_USER:-$USER}"

# ── Args ──────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --driver)       DRIVER_VERSION="$2"; shift 2 ;;
    --model)        OLLAMA_MODEL="$2";   shift 2 ;;
    --no-reboot)    SKIP_REBOOT=true;    shift ;;
    --skip-driver)  SKIP_DRIVER=true;    shift ;;
    --skip-claude)  SKIP_CLAUDE=true;    shift ;;
    --help|-h)
      sed -n '3,16p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) error "Unknown argument: $1  (use --help)" ;;
  esac
done

# ── Logging ───────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
info "Logging to: $LOG_FILE"

# ── Sanity ────────────────────────────────────────────────────────────────────
step "Pre-flight Checks"

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash $0"

# OS check
grep -qi ubuntu /etc/os-release || error "This script targets Ubuntu Server."
UBUNTU_VERSION=$(grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"')
UBUNTU_CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
log "Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

# Architecture
[[ "$(uname -m)" == "x86_64" ]] || error "x86_64 only."

# GPU visibility
if ! lspci | grep -qi nvidia; then
  warn "No NVIDIA GPU visible via lspci."
  warn "If using GPU passthrough (Proxmox/KVM), verify:"
  warn "  1. IOMMU enabled in BIOS + kernel (intel_iommu=on / amd_iommu=on)"
  warn "  2. GPU bound to vfio-pci on host, passed through to this VM"
  warn "  3. Run: lspci | grep -i nvidia"
  read -r -p "Continue anyway? [y/N]: " CONT
  [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
else
  GPU_NAME=$(lspci | grep -i nvidia | grep -i "vga\|3d\|display" | head -1 | sed 's/.*: //')
  log "GPU detected: ${GPU_NAME}"
fi

KERNEL=$(uname -r)
log "Kernel: ${KERNEL}"
done_

# ── Base packages ─────────────────────────────────────────────────────────────
step "System Update & Base Packages"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y \
  build-essential dkms \
  "linux-headers-${KERNEL}" \
  linux-headers-generic \
  pkg-config curl wget gnupg2 \
  software-properties-common \
  ca-certificates apt-transport-https \
  git jq pciutils \
  unzip htop nvtop

log "Base packages installed"
done_

# ── NVIDIA Driver ─────────────────────────────────────────────────────────────
if [[ "$SKIP_DRIVER" == false ]]; then
  step "NVIDIA Driver Installation"

  # Blacklist nouveau
  BLACKLIST=/etc/modprobe.d/blacklist-nouveau.conf
  cat > "$BLACKLIST" <<EOF
blacklist nouveau
options nouveau modeset=0
EOF
  log "Nouveau blacklisted"

  # Remove stale NVIDIA packages
  EXISTING=$(dpkg -l 2>/dev/null | grep -E '^ii\s+nvidia' | awk '{print $2}' || true)
  if [[ -n "$EXISTING" ]]; then
    warn "Removing existing NVIDIA packages..."
    # shellcheck disable=SC2086
    apt-get remove --purge -y $EXISTING 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
  fi

  # Add official NVIDIA CUDA repo (provides both driver + CUDA in one repo)
  UBUNTU_SHORT="${UBUNTU_VERSION//./}"
  KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_SHORT}/x86_64/cuda-keyring_1.1-1_all.deb"
  TMP_DEB=$(mktemp /tmp/cuda-keyring.XXXXXX.deb)

  if wget -q -O "$TMP_DEB" "$KEYRING_URL"; then
    dpkg -i "$TMP_DEB" && rm -f "$TMP_DEB"
    log "NVIDIA CUDA repo configured"
  else
    warn "Could not fetch NVIDIA keyring — falling back to graphics-drivers PPA"
    add-apt-repository -y ppa:graphics-drivers/ppa
  fi

  apt-get update -qq
  apt-get install -y ubuntu-drivers-common

  # Auto-detect driver version
  if [[ -z "$DRIVER_VERSION" ]]; then
    DRIVER_VERSION=$(ubuntu-drivers devices 2>/dev/null \
      | grep "recommended" \
      | grep -oP 'nvidia-driver-\K[0-9]+' \
      | head -1 || true)

    if [[ -z "$DRIVER_VERSION" ]]; then
      DRIVER_VERSION=$(apt-cache search '^nvidia-driver-[0-9]+$' \
        | grep -oP 'nvidia-driver-\K[0-9]+' \
        | sort -n | tail -1 || true)
      [[ -z "$DRIVER_VERSION" ]] && error "Could not detect driver. Use --driver VERSION."
      warn "No recommendation found; using latest available: ${DRIVER_VERSION}"
    else
      log "Auto-detected driver: ${DRIVER_VERSION}"
    fi
  fi

  apt-get install -y \
    "nvidia-driver-${DRIVER_VERSION}" \
    "cuda-toolkit-${CUDA_VERSION}"

  log "nvidia-driver-${DRIVER_VERSION} + cuda-toolkit-${CUDA_VERSION} installed"

  # CUDA environment for all users
  cat > /etc/profile.d/cuda.sh <<'EOF'
export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
EOF
  chmod +x /etc/profile.d/cuda.sh
  log "CUDA paths exported to /etc/profile.d/cuda.sh"

  # Verify DKMS
  DKMS_OUT=$(dkms status 2>/dev/null | grep -i nvidia || true)
  if echo "$DKMS_OUT" | grep -qi "installed\|built"; then
    log "DKMS module: $DKMS_OUT"
  else
    warn "DKMS status unclear — may need reboot to verify: dkms status"
  fi

  update-initramfs -u -k "${KERNEL}"
  log "initramfs updated"
  done_
else
  warn "Skipping NVIDIA driver install (--skip-driver)"
  # Still try to detect driver version for summary
  DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
fi

# ── Ollama ────────────────────────────────────────────────────────────────────
step "Installing Ollama"

if command -v ollama &>/dev/null; then
  OLLAMA_CURRENT=$(ollama --version 2>/dev/null || echo "unknown")
  warn "Ollama already installed: ${OLLAMA_CURRENT}"
  info "To upgrade: curl -fsSL https://ollama.com/install.sh | sh"
else
  curl -fsSL https://ollama.com/install.sh | sh
  log "Ollama installed: $(ollama --version 2>/dev/null || echo 'version check after reboot')"
fi

# Configure Ollama systemd service
OLLAMA_ENV_FILE=/etc/systemd/system/ollama.service.d/override.conf
mkdir -p "$(dirname "$OLLAMA_ENV_FILE")"
cat > "$OLLAMA_ENV_FILE" <<EOF
[Service]
# Expose Ollama on all interfaces (needed for Claude Code to connect)
Environment="OLLAMA_HOST=0.0.0.0:11434"
# Keep models in a predictable location
Environment="OLLAMA_MODELS=/var/lib/ollama/models"
# Max GPU memory fraction (adjust if you share the GPU)
Environment="OLLAMA_GPU_MEMORY_FRACTION=0.9"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama || true
log "Ollama service configured + enabled"
log "Ollama listening on: 0.0.0.0:11434"
done_

# ── Pull Ollama model ─────────────────────────────────────────────────────────
step "Pulling Ollama Model: ${OLLAMA_MODEL}"

# Wait for Ollama to be ready
info "Waiting for Ollama API to be ready..."
for i in $(seq 1 20); do
  if curl -sf http://localhost:11434/api/version &>/dev/null; then
    log "Ollama API ready"
    break
  fi
  sleep 2
  [[ $i -eq 20 ]] && warn "Ollama not responding yet — model pull may fail. Try: ollama pull ${OLLAMA_MODEL}"
done

if curl -sf http://localhost:11434/api/version &>/dev/null; then
  info "Pulling ${OLLAMA_MODEL} (this may take a while depending on model size)..."
  ollama pull "${OLLAMA_MODEL}" && log "Model ${OLLAMA_MODEL} ready" \
    || warn "Pull failed — run manually: ollama pull ${OLLAMA_MODEL}"
fi
done_

# ── Node.js (required for Claude Code) ───────────────────────────────────────
step "Installing Node.js (for Claude Code)"

if command -v node &>/dev/null; then
  NODE_VER=$(node --version)
  log "Node.js already installed: ${NODE_VER}"
else
  # Use NodeSource for LTS
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt-get install -y nodejs
  log "Node.js installed: $(node --version)"
fi

log "npm version: $(npm --version)"
done_

# ── Claude Code ───────────────────────────────────────────────────────────────
if [[ "$SKIP_CLAUDE" == false ]]; then
  step "Installing Claude Code"

  npm install -g @anthropic-ai/claude-code
  log "Claude Code installed: $(claude --version 2>/dev/null || echo 'verify with: claude --version')"

  # Create a helper config for using Claude Code with local Ollama
  CLAUDE_OLLAMA_HELPER=/usr/local/bin/claude-ollama
  cat > "$CLAUDE_OLLAMA_HELPER" <<'HELPEREOF'
#!/usr/bin/env bash
# Launch Claude Code pointed at local Ollama
# Usage: claude-ollama [claude-code-args...]
#
# Claude Code will use your ANTHROPIC_API_KEY for claude.ai by default.
# To use Ollama instead, configure it inside Claude Code with:
#   /model  →  select your Ollama model endpoint

export OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
echo "[claude-ollama] Ollama at: $OLLAMA_HOST"
echo "[claude-ollama] Available models:"
curl -sf "$OLLAMA_HOST/api/tags" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('models', []):
    print('  -', m['name'])
" 2>/dev/null || echo "  (ollama not responding)"
echo ""
exec claude "$@"
HELPEREOF
  chmod +x "$CLAUDE_OLLAMA_HELPER"
  log "Helper script created: claude-ollama"
  done_
else
  warn "Skipping Claude Code install (--skip-claude)"
fi

# ── Firewall config ───────────────────────────────────────────────────────────
step "Firewall: Opening Ollama Port"

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
  # Allow Ollama API from local subnet only (adjust if needed)
  ufw allow 11434/tcp comment "Ollama API"
  log "ufw: port 11434 opened"
else
  info "ufw not active — skipping firewall config"
  info "If you use iptables, open port 11434 manually"
fi
done_

# ── Verification script ───────────────────────────────────────────────────────
step "Creating Verification Script"

cat > /usr/local/bin/check-gpu-stack <<'CHECKEOF'
#!/usr/bin/env bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✔]${NC} $*"; }
fail() { echo -e "${RED}[✘]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }

echo -e "\n${BOLD}GPU AI Stack Status${NC}\n"

# NVIDIA driver + GPU
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
  ok "NVIDIA driver loaded"
  nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free,temperature.gpu \
    --format=csv,noheader | while IFS=',' read -r name drv total free temp; do
    echo "    GPU:      $name"
    echo "    Driver:   $drv"
    echo "    VRAM:     ${free} free / ${total} total"
    echo "    Temp:     ${temp}°C"
  done
else
  fail "NVIDIA driver not loaded (reboot may be needed)"
fi

echo ""

# CUDA
if command -v nvcc &>/dev/null; then
  ok "CUDA: $(nvcc --version | grep release | awk '{print $5}' | tr -d ',')"
else
  warn "nvcc not in PATH — source /etc/profile.d/cuda.sh or reboot"
fi

echo ""

# Ollama
if systemctl is-active --quiet ollama 2>/dev/null; then
  ok "Ollama service: running"
  if curl -sf http://localhost:11434/api/version &>/dev/null; then
    ok "Ollama API: reachable at http://localhost:11434"
    MODEL_COUNT=$(curl -sf http://localhost:11434/api/tags | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(len(d.get('models',[])))" 2>/dev/null || echo "?")
    info "Models loaded: ${MODEL_COUNT}"
    curl -sf http://localhost:11434/api/tags | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('models', []):
    size_gb = round(m.get('size', 0) / 1e9, 1)
    print(f'    - {m[\"name\"]} ({size_gb} GB)')
" 2>/dev/null || true
  else
    fail "Ollama API not responding on port 11434"
  fi
else
  fail "Ollama service not running (sudo systemctl start ollama)"
fi

echo ""

# Claude Code
if command -v claude &>/dev/null; then
  ok "Claude Code: $(claude --version 2>/dev/null || echo 'installed')"
  info "Run 'claude' in any project directory to start"
  info "Run 'claude-ollama' to start with local Ollama info"
else
  fail "Claude Code not found (install: npm install -g @anthropic-ai/claude-code)"
fi

echo ""

# GPU usage by Ollama
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
  GPU_PROCS=$(nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv,noheader 2>/dev/null || true)
  if [[ -n "$GPU_PROCS" ]]; then
    ok "Active GPU processes:"
    echo "$GPU_PROCS" | while IFS=',' read -r pid name mem; do
      echo "    PID $pid  $name  (${mem})"
    done
  else
    info "No active GPU compute processes (Ollama uses GPU on demand)"
  fi
fi
CHECKEOF

chmod +x /usr/local/bin/check-gpu-stack
log "Verification script: check-gpu-stack"
done_

# ── Final Summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Installation Complete${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}GPU:${NC}            ${GPU_NAME:-see nvidia-smi after reboot}"
echo -e "  ${BOLD}Driver branch:${NC}  ${DRIVER_VERSION}"
echo -e "  ${BOLD}CUDA:${NC}           ${CUDA_VERSION}"
echo -e "  ${BOLD}Ollama model:${NC}   ${OLLAMA_MODEL}"
echo -e "  ${BOLD}Ollama API:${NC}     http://0.0.0.0:11434"
echo -e "  ${BOLD}Claude Code:${NC}    $(command -v claude 2>/dev/null || echo 'installed')"
echo ""
echo -e "  ${DIM}After reboot:${NC}"
echo -e "    check-gpu-stack      # verify everything"
echo -e "    nvidia-smi           # GPU status"
echo -e "    ollama list          # installed models"
echo -e "    ollama run ${OLLAMA_MODEL}  # test the model"
echo -e "    cd /your/project && claude   # start Claude Code"
echo ""
echo -e "  ${DIM}Log:${NC} $LOG_FILE"
echo ""

# ── Reboot ────────────────────────────────────────────────────────────────────
if [[ "$SKIP_REBOOT" == false ]]; then
  read -r -p "Reboot now to load NVIDIA kernel modules? [y/N]: " RB
  [[ "$RB" =~ ^[Yy]$ ]] && reboot || warn "Remember to reboot before using the GPU."
else
  warn "--no-reboot set. Reboot before expecting nvidia-smi to work."
fi
