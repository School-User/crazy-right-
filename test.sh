#!/bin/bash

# Define output file path
OUTPUT_FILE="$HOME/Desktop/universal_audit_$(date +%Y%m%d_%H%M%S).txt"

{
    echo "=========================================="
    echo "       UNIVERSAL SYSTEM AUDIT             "
    echo "=========================================="
    echo ""

    echo "--- OS & KERNEL ---"
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo "Distro: $PRETTY_NAME"
    fi
    uname -sr
    echo ""

    echo "--- DESKTOP ENVIRONMENT ---"
    echo "Desktop: ${XDG_CURRENT_DESKTOP:-Unknown}"
    echo "Session: ${XDG_SESSION_TYPE:-Unknown}"
    echo ""

    echo "--- PACKAGE COUNT ---"
    # Check for various package managers
    if command -v dpkg &>/dev/null; then echo "Apt packages: $(dpkg -l | wc -l)"; fi
    if command -v rpm &>/dev/null; then echo "RPM packages: $(rpm -qa | wc -l)"; fi
    if command -v pacman &>/dev/null; then echo "Pacman packages: $(pacman -Qq | wc -l)"; fi
    if command -v zypper &>/dev/null; then echo "Zypper packages: $(rpm -qa | wc -l)"; fi
    if command -v flatpak &>/dev/null; then echo "Flatpaks: $(flatpak list | wc -l)"; fi
    if command -v snap &>/dev/null; then echo "Snaps: $(snap list | wc -l)"; fi
    echo ""

    echo "--- INSTALLED APPLICATIONS ---"
    # Lists apps registered in the system applications folders
    ls /usr/share/applications/*.desktop 2>/dev/null | xargs -n 1 basename | sed 's/.desktop//' | sort | column
    echo ""

    echo "--- RECENT CONFIG CHANGES (Global /etc - Last 7 Days) ---"
    find /etc -maxdepth 2 -type f -mtime -7 2>/dev/null | head -n 15
    echo ""

    echo "--- RECENT USER CONFIG CHANGES (Home - Last 7 Days) ---"
    find "$HOME" -maxdepth 2 -name ".*" -mtime -7 2>/dev/null | head -n 15

} > "$OUTPUT_FILE"

echo "Report generated successfully: $OUTPUT_FILE"
