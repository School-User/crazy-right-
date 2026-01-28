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
    if command -v dpkg &>/dev/null; then echo "Apt packages: $(dpkg -l | wc -l)"; fi
    if command -v rpm &>/dev/null; then echo "RPM packages: $(rpm -qa | wc -l)"; fi
    if command -v pacman &>/dev/null; then echo "Pacman packages: $(pacman -Qq | wc -l)"; fi
    if command -v zypper &>/dev/null; then echo "Zypper packages: $(rpm -qa | wc -l)"; fi
    if command -v flatpak &>/dev/null; then echo "Flatpaks: $(flatpak list | wc -l)"; fi
    if command -v snap &>/dev/null; then echo "Snaps: $(snap list | wc -l)"; fi
    echo ""

    echo "--- INSTALLED APPLICATIONS ---"
    ls /usr/share/applications/*.desktop 2>/dev/null | xargs -n 1 basename | sed 's/.desktop//' | sort | column
    echo ""

    echo "--- RECENT CONFIG CHANGES (Global /etc - Last 7 Days) ---"
    # Added 'ls -lt' to sort by time (newest first)
    find /etc -maxdepth 2 -type f -mtime -7 2>/dev/null -exec ls -lt {} + | head -n 100 | awk '{print $NF}'
    echo ""

    echo "--- RECENT USER CONFIG CHANGES (Home - Last 90 Days) ---"
    # Added 'ls -lt' to sort by time (newest first) and kept the 90-day window
    find "$HOME" -maxdepth 2 -name ".*" -mtime -90 2>/dev/null -exec ls -lt {} + | head -n 100 | awk '{print $NF}'

} > "$OUTPUT_FILE"

echo "Report generated successfully: $OUTPUT_FILE"
