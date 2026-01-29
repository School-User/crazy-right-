#!/bin/bash

# ==============================================================================
# PROJECT: AuditTrail-180 (Linux Forensic Edition v3.0)
# AUTHOR:  CyberPatriot Open Source Collective
# PURPOSE: Full system audit (OS, Packages, Files, Logs) with valid permissions.
# ==============================================================================

# Strict Mode: Exist on error, treat unset variables as errors
set -u

# --- Configuration ---
DEFAULT_DAYS=180
# High-priority directories to scan
CRITICAL_PATHS=( "/etc" "/usr/local/bin" "/usr/local/sbin" "/opt" "/root" "/var/spool/cron" "/boot" )

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- Output Setup Logic ---
init_output_path() {
    # 1. Identify the Real User (even behind sudo)
    if [ -n "${SUDO_USER-}" ]; then
        REAL_USER="$SUDO_USER"
    else
        REAL_USER="$(whoami)"
    fi

    # 2. Get Real User's Home Directory
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

    # 3. Determine Output Target (Desktop vs Home)
    DATE_TAG=$(date +%Y-%m-%d_%H%M)
    FILENAME="AuditTrail_Report_${HOSTNAME}_${DATE_TAG}.txt"
    
    if [ -d "$REAL_HOME/Desktop" ]; then
        REPORT_PATH="$REAL_HOME/Desktop/$FILENAME"
    else
        REPORT_PATH="$REAL_HOME/$FILENAME"
    fi

    echo "$REPORT_PATH"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}[!] Error: This script must be run as root.${NC}" 
       exit 1
    fi
}

log_msg() {
    local LEVEL="$1"
    local MSG="$2"
    local COLOR="$NC"
    
    case $LEVEL in
        "INFO") COLOR="$BLUE" ;;
        "OK")   COLOR="$GREEN" ;;
        "WARN") COLOR="$YELLOW" ;;
    esac

    # Console Output
    echo -e "${COLOR}[*] ${MSG}${NC}"
    # File Output (Strip color codes)
    echo "[$(date +%T)] $MSG" >> "$REPORT_PATH"
}

section_header() {
    echo -e "\n${BOLD}=== $1 ===${NC}"
    echo -e "\n========================================\n$1\n========================================" >> "$REPORT_PATH"
}

timestamp_to_date() {
    date -d "@$1" "+%Y-%m-%d %H:%M:%S"
}

# --- Module 1: System Info ---
audit_sysinfo() {
    section_header "1. SYSTEM & ENVIRONMENT INFO"
    log_msg "INFO" "Gathering OS and Desktop details..."

    # Detect OS Name cleanly
    if [ -f /etc/os-release ]; then
        # Run in subshell to avoid var pollution
        OS_NAME=$(source /etc/os-release && echo "$PRETTY_NAME")
    else
        OS_NAME="$(uname -s) $(uname -r)"
    fi

    # Detect Desktop Environment (Context often lost in sudo, checked primarily via XDG)
    CURRENT_DE="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-Headless/Unknown}}"
    
    # Dump details to report
    {
        echo "Hostname:    $(hostname)"
        echo "Distro:      $OS_NAME"
        echo "Kernel:      $(uname -sr)"
        echo "Desktop Env: $CURRENT_DE"
        echo "Arch:        $(uname -m)"
        echo "Boot Time:   $(uptime -s)"
    } >> "$REPORT_PATH"
}

# --- Module 2: Package Logs ---
audit_packages() {
    section_header "2. PACKAGE INSTALLATION HISTORY (Last $DAYS Days)"
    
    # APT (Debian/Ubuntu)
    if [ -f "/var/log/apt/history.log" ]; then
        log_msg "INFO" "Parsing APT history logs..."
        CUTOFF_EPOCH=$(date -d "-$DAYS days" +%s)
        
        # Single line find+grep to avoid loop errors
        grep -hE "^Start-Date:|^Commandline:" /var/log/apt/history.log /var/log/apt/history.log.*.gz 2>/dev/null | while read -r line; do 
            if [[ "$line" == Start-Date:* ]]; then
                LOG_DATE=$(echo "$line" | cut -d' ' -f2)
                LOG_EPOCH=$(date -d "$LOG_DATE" +%s 2>/dev/null)
                
                # Check if installation is newer than cutoff
                if [[ -n "$LOG_EPOCH" && "$LOG_EPOCH" -ge "$CUTOFF_EPOCH" ]]; then
                    read -r cmd_line
                    CLEAN_CMD="${cmd_line#Commandline: }"
                    echo "[$LOG_DATE] APT: $CLEAN_CMD" >> "$REPORT_PATH"
                fi
            fi
        done

    # RPM (RHEL/CentOS)
    elif command -v rpm &> /dev/null; then
        log_msg "INFO" "Querying RPM database..."
        CUTOFF_EPOCH=$(date -d "-$DAYS days" +%s)
        
        rpm -qa --queryformat '%{INSTALLTIME} %{NAME}-%{VERSION}\n' | while read -r ts name; do
            if [[ "$ts" -gt "$CUTOFF_EPOCH" ]]; then
                human_date=$(timestamp_to_date "$ts")
                echo "[$human_date] RPM: $name" >> "$REPORT_PATH"
            fi
        done

    # Pacman (Arch)
    elif [ -f "/var/log/pacman.log" ]; then
        log_msg "INFO" "Parsing Pacman logs..."
        CUTOFF_ISO=$(date -d "-$DAYS days" +%Y-%m-%d)
        grep "installed" /var/log/pacman.log | while read -r line; do
            log_date=$(echo "$line" | cut -d'T' -f1 | tr -d '[')
            if [[ "$log_date" > "$CUTOFF_ISO" ]]; then
                echo "PACMAN: $line" >> "$REPORT_PATH"
            fi
        done
    else
        log_msg "WARN" "No supported package manager detected."
    fi
}

# --- Module 3: Filesystem ---
audit_filesystem() {
    section_header "3. MODIFIED SYSTEM FILES (Top 50 Recently Modified)"
    log_msg "INFO" "Scanning critical paths..."
    
    echo "Scan Paths: ${CRITICAL_PATHS[*]}" >> "$REPORT_PATH"
    
    # robust find command (no trailing slash issues, no line continuations)
    find "${CRITICAL_PATHS[@]}" -xdev -type f -mtime -"$DAYS" ! -path "*/.cache/*" ! -path "*/tmp/*" ! -path "*/runs/*" -printf "%T@ [%Tc] %p\n" 2>/dev/null | sort -rn | head -n 50 | cut -d' ' -f2- >> "$REPORT_PATH"
}

# --- Module 4: Auth Logs ---
audit_sudo() {
    section_header "4. SUDO/AUTH ACTIVITY"
    log_msg "INFO" "Extracting recent sudo commands..."
    
    TARGET_LOG=""
    [ -f "/var/log/auth.log" ] && TARGET_LOG="/var/log/auth.log"
    [ -f "/var/log/secure" ] && TARGET_LOG="/var/log/secure"
    
    if [ -n "$TARGET_LOG" ]; then
        # Extract commands, take last 50
        grep "COMMAND=" "$TARGET_LOG" | tail -n 50 >> "$REPORT_PATH"
    else
        echo "No standard auth log found." >> "$REPORT_PATH"
    fi
}

# --- Execution Flow ---

check_root

if [ $# -eq 0 ]; then
    DAYS=$DEFAULT_DAYS
else
    DAYS=$1
fi

REPORT_PATH=$(init_output_path)

# Initialize Report
echo "AUDIT REPORT" > "$REPORT_PATH"
echo "Generated: $(date)" >> "$REPORT_PATH"
echo "Target Host: $HOSTNAME" >> "$REPORT_PATH"
echo "Lookback: $DAYS Days" >> "$REPORT_PATH"
echo "----------------------------------------" >> "$REPORT_PATH"

# Console Banner
clear
echo -e "${BLUE}${BOLD}AuditTrail-180${NC}"
echo "----------------------------------------"
log_msg "INFO" "Starting Audit on: $HOSTNAME"
log_msg "OK"   "Report Target: $REPORT_PATH"

# Run Modules
audit_sysinfo
audit_packages
audit_filesystem
audit_sudo

# Fix Permissions (Give file back to user)
if [ -n "${SUDO_USER-}" ]; then
    chown "$SUDO_USER" "$REPORT_PATH"
    log_msg "OK" "Permissions ownership transferred to user: $SUDO_USER"
fi

echo -e "\n${GREEN}${BOLD}COMPLETED.${NC}"
echo -e "Review the full report at: ${BOLD}$REPORT_PATH${NC}"
