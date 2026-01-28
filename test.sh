#!/bin/bash

# Define output file path
OUTPUT_FILE="$HOME/Desktop/system_audit_$(date +%Y%m%d_%H%M%S).txt"

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

    echo "--- GLOBAL CONFIG LOCATIONS & TIME (/etc - Last 180 Days) ---"
    # Logic: find files modified in last 180 days, sort by time, show Month/Day/Time and Path
    find /etc -maxdepth 3 -type f -mtime -180 2>/dev/null -exec ls -lt {} + | head -n 200 | awk '{print $6, $7, $8, "->", $NF}'
    echo ""

    echo "--- USER CONFIG LOCATIONS & TIME ($HOME - Last 180 Days) ---"
    # Logic: find hidden files in Home modified in last 180 days, sort by time, show Month/Day/Time and Path
    find "$HOME" -maxdepth 3 -name ".*" -mtime -180 2>/dev/null -exec ls -lt {} + | head -n 200 | awk '{print $6, $7, $8, "->", $NF}'

} > "$OUTPUT_FILE"

echo "Audit complete! Your report is here: $OUTPUT_FILE"
