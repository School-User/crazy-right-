#!/usr/bin/env bash
# remove_ai_tools.sh — Remove common AI/LLM tools from a Linux system
# Run as root or with sudo privileges.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
removed() { echo -e "${RED}[-]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

# ─── Ollama ────────────────────────────────────────────────────────────────────
remove_ollama() {
  if systemctl is-active --quiet ollama 2>/dev/null; then
    info "Stopping Ollama service..."
    systemctl stop ollama
    systemctl disable ollama
  fi
  [[ -f /etc/systemd/system/ollama.service ]] && rm -f /etc/systemd/system/ollama.service
  systemctl daemon-reload 2>/dev/null || true

  if command -v ollama &>/dev/null; then
    rm -f "$(command -v ollama)"
    removed "Ollama binary removed."
  fi

  # Remove model data
  for dir in /usr/share/ollama /root/.ollama /home/*/.ollama; do
    if [[ -d "$dir" ]]; then
      warn "Removing Ollama data: $dir"
      rm -rf "$dir"
    fi
  done
}

# ─── LM Studio (AppImage / extracted) ─────────────────────────────────────────
remove_lmstudio() {
  for path in /home/*/LM\ Studio* /home/*/.lmstudio /home/*/lm-studio* \
               /opt/lm-studio* /root/.lmstudio; do
    if [[ -e "$path" ]]; then
      warn "Removing LM Studio path: $path"
      rm -rf "$path"
      removed "LM Studio removed: $path"
    fi
  done
}

# ─── LocalAI ──────────────────────────────────────────────────────────────────
remove_localai() {
  if systemctl is-active --quiet local-ai 2>/dev/null; then
    systemctl stop local-ai; systemctl disable local-ai
  fi
  for path in /usr/local/bin/local-ai /opt/local-ai /etc/local-ai /var/lib/local-ai; do
    if [[ -e "$path" ]]; then rm -rf "$path"; removed "LocalAI removed: $path"; fi
  done
}

# ─── Jan.ai ───────────────────────────────────────────────────────────────────
remove_jan() {
  for path in /home/*/jan /home/*/.config/jan /opt/jan*; do
    if [[ -e "$path" ]]; then rm -rf "$path"; removed "Jan removed: $path"; fi
  done
}

# ─── Open WebUI ───────────────────────────────────────────────────────────────
remove_open_webui() {
  # Docker container
  if command -v docker &>/dev/null; then
    if docker ps -a --format '{{.Names}}' | grep -qi "open-webui"; then
      docker rm -f open-webui 2>/dev/null || true
      removed "Open WebUI Docker container removed."
    fi
    if docker images --format '{{.Repository}}' | grep -qi "open-webui"; then
      docker rmi ghcr.io/open-webui/open-webui 2>/dev/null || true
      removed "Open WebUI Docker image removed."
    fi
  fi
  # pip / pipx install
  pip uninstall -y open-webui 2>/dev/null && removed "open-webui pip package removed." || true
  command -v pipx &>/dev/null && pipx uninstall open-webui 2>/dev/null || true
}

# ─── AnythingLLM ──────────────────────────────────────────────────────────────
remove_anythingllm() {
  for path in /home/*/anythingllm /opt/anythingllm* /home/*/.config/anythingllm; do
    if [[ -e "$path" ]]; then rm -rf "$path"; removed "AnythingLLM removed: $path"; fi
  done
}

# ─── Claude Code (npm global) ─────────────────────────────────────────────────
remove_claude_code() {
  if command -v claude &>/dev/null; then
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null && removed "Claude Code (npm) removed." || true
  fi
}

# ─── Python AI packages (pip) ─────────────────────────────────────────────────
remove_pip_ai_packages() {
  local pkgs=(
    openai anthropic langchain langchain-community langchain-core
    llama-cpp-python transformers accelerate diffusers
    huggingface-hub sentence-transformers chromadb faiss-cpu
    autogen pyautogen crewai guidance outlines litellm
    ollama-python openai-whisper faster-whisper
  )
  for pkg in "${pkgs[@]}"; do
    if pip show "$pkg" &>/dev/null 2>&1; then
      pip uninstall -y "$pkg" 2>/dev/null && removed "pip: $pkg removed."
    fi
  done
}

# ─── Hugging Face cache ────────────────────────────────────────────────────────
remove_hf_cache() {
  for dir in /home/*/.cache/huggingface /root/.cache/huggingface; do
    if [[ -d "$dir" ]]; then
      warn "Removing Hugging Face cache: $dir  (may be large)"
      rm -rf "$dir"
      removed "HF cache removed: $dir"
    fi
  done
}

# ─── Main ──────────────────────────────────────────────────────────────────────
echo "======================================================"
echo " AI Tools Removal Script"
echo "======================================================"
echo ""

remove_ollama
remove_lmstudio
remove_localai
remove_jan
remove_open_webui
remove_anythingllm
remove_claude_code
remove_pip_ai_packages
remove_hf_cache

echo ""
echo "======================================================"
info "Done. Reboot recommended to clear any lingering processes."
echo "======================================================"
