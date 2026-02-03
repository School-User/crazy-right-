#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run with sudo."
  exit 1
fi

OUT="full_system_report.txt"
USER_HOME=$(eval echo "~$SUDO_USER")

echo "Starting data collection... this may take a minute."

{
    echo "=========================================================="
    echo "SYSTEM AUDIT REPORT: $(hostname)"
    echo "DATE: $(date)"
    echo "=========================================================="

    echo -e "\n[1. HARDWARE & OS SPECS]"
    hostnamectl
    echo -e "\n--- CPU ---"
    lscpu
    echo -e "\n--- MEMORY ---"
    free -h
    echo -e "\n--- STORAGE ---"
    lsblk -f

    echo -e "\n[2. INSTALLED SOFTWARE]"
    echo "--- APT PACKAGES ---"
    dpkg --get-selections
    echo -e "\n--- FLATPAK LIST ---"
    flatpak list --columns=application,version 2>/dev/null

    echo -e "\n[3. NETWORK CONFIGURATION]"
    ip addr
    echo -e "\n--- ROUTES ---"
    ip route

    echo -e "\n[4. SYSTEM CONFIGURATION FILES (/etc)]"
    # Find text files in /etc (limit depth to avoid massive log dumps)
    find /etc -maxdepth 2 -type f -not -path '*/.*' | while read -r file; do
        if file "$file" | grep -q "text"; then
            echo -e "\n--- START FILE: $file ---"
            cat "$file" 2>/dev/null
            echo -e "--- END FILE: $file ---"
        fi
    done

    echo -e "\n[5. USER DOTFILES]"
    # Captures text-based config files in the home directory
    find "$USER_HOME" -maxdepth 1 -type f -name ".*" | while read -r file; do
        if file "$file" | grep -q "text"; then
            echo -e "\n--- START USER FILE: $file ---"
            cat "$file" 2>/dev/null
            echo -e "--- END USER FILE: $file ---"
        fi
    done

} > "$OUT"

# Fix ownership so your user can open the text file easily
chown "$SUDO_USER":"$SUDO_USER" "$OUT"

echo "Complete. Report saved to: $OUT"
