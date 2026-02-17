#!/bin/bash
# ============================================================
# User Management Script
# Based on Readme file - FTP Server (vsftpd) / Spider-Verse scenario
# Run as root: sudo bash user_management.sh
# ============================================================

# ============================================================
# CONFIGURATION - From Readme file
# ============================================================

# Authorized Administrators (with sudo privileges)
ADMIN_USERS=(
    "chowe"
    "miles"
    "gwen"
    "peter"
)

# Authorized regular users
REGULAR_USERS=(
    "peni"
    "noir"
    "ham"
    "stan"
    "steve"
    "miguel"
    "jefferson"
    "rio"
    "may"
    "jessica"
    "pavitr"
    "maryjane"
    "auntmay"   # New account - spider department
)

# All authorized users combined
AUTHORIZED_USERS=("${ADMIN_USERS[@]}" "${REGULAR_USERS[@]}")

# Passwords for admin users (from Readme)
declare -A ADMIN_PASSWORDS=(
    ["chowe"]="Cyb3rCont3st"
    ["miles"]="Sup3rHum4n16"
    ["gwen"]="RadioAc7!V65"
    ["peter"]="Dim3Ns!on616"
)

# ============================================================
# TASK 6: Spider department group + new account
# ============================================================
SPIDER_GROUP="spider"

# Existing authorized users to add to spider group
SPIDER_MEMBERS=("may" "peni" "stan" "miguel")

# New account to create and add to spider group
NEW_SPIDER_ACCOUNT="auntmay"

# ============================================================
# System/built-in users to NEVER touch
# ============================================================
SYSTEM_USERS=(
    "root" "daemon" "bin" "sys" "sync" "games" "man" "lp"
    "mail" "news" "uucp" "proxy" "www-data" "backup" "list"
    "irc" "gnats" "nobody" "systemd-network" "systemd-resolve"
    "messagebus" "syslog" "avahi" "uuidd" "dnsmasq" "usbmux"
    "rtkit" "cups-pk-helper" "speech-dispatcher" "whoopsie"
    "kernoops" "pulse" "avahi-autoipd" "saned" "colord"
    "hplip" "geoclue" "sshd" "pollinate" "landscape" "ubuntu"
    "systemd-timesync" "systemd-coredump" "ftp" "vsftpd"
)

# ============================================================
# HELPER FUNCTIONS
# ============================================================

is_system_user() {
    local user="$1"
    for sys_user in "${SYSTEM_USERS[@]}"; do
        [[ "$user" == "$sys_user" ]] && return 0
    done
    return 1
}

is_authorized() {
    local user="$1"
    for auth_user in "${AUTHORIZED_USERS[@]}"; do
        [[ "$user" == "$auth_user" ]] && return 0
    done
    return 1
}

# ============================================================
# TASK 1: Remove unauthorized users
# ============================================================
echo "=========================================="
echo "[TASK 1] Removing unauthorized users..."
echo "=========================================="

while IFS=: read -r username _ uid _; do
    if [[ "$uid" -ge 1000 && "$uid" -lt 60000 ]]; then
        if ! is_system_user "$username" && ! is_authorized "$username"; then
            echo "  Removing unauthorized user: $username"
            userdel -r "$username" 2>/dev/null
            echo "  [DONE] Removed $username"
        fi
    fi
done < /etc/passwd

# ============================================================
# TASK 2: Add missing authorized users
# ============================================================
echo ""
echo "=========================================="
echo "[TASK 2] Adding missing authorized users..."
echo "=========================================="

for user in "${AUTHORIZED_USERS[@]}"; do
    if ! id "$user" &>/dev/null; then
        echo "  Adding missing user: $user"
        useradd -m -s /bin/bash "$user"
        echo "  [DONE] Added $user"
    else
        echo "  User $user already exists, skipping."
    fi
done

# ============================================================
# TASK 3: Unlock all authorized users
# ============================================================
echo ""
echo "=========================================="
echo "[TASK 3] Unlocking all authorized users..."
echo "=========================================="

for user in "${AUTHORIZED_USERS[@]}"; do
    if id "$user" &>/dev/null; then
        STATUS=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
        if [[ "$STATUS" == "L" || "$STATUS" == "LK" ]]; then
            passwd -U "$user" 2>/dev/null
            usermod -U "$user" 2>/dev/null
            echo "  Unlocked: $user"
        else
            echo "  $user is already unlocked (status: $STATUS)"
        fi
    fi
done

# ============================================================
# TASK 4: Set passwords for all users
# ============================================================
echo ""
echo "=========================================="
echo "[TASK 4] Setting/verifying passwords..."
echo "=========================================="

# Set known passwords for admins (from Readme)
for admin in "${ADMIN_USERS[@]}"; do
    if id "$admin" &>/dev/null; then
        echo "$admin:${ADMIN_PASSWORDS[$admin]}" | chpasswd
        echo "  Set Readme password for admin: $admin"
    fi
done

# Set default password for regular users with no password
for user in "${REGULAR_USERS[@]}"; do
    if id "$user" &>/dev/null; then
        PASS_STATUS=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
        if [[ "$PASS_STATUS" == "NP" ]]; then
            echo "$user:ChangeMe123!" | chpasswd
            echo "  Set default password for: $user"
        else
            echo "  $user already has a password."
        fi
    fi
done

# ============================================================
# TASK 5: Ensure correct group memberships
#         Admins -> sudo | Regular users -> users group
#         Remove unauthorized users from all groups
# ============================================================
echo ""
echo "=========================================="
echo "[TASK 5] Fixing group memberships..."
echo "=========================================="

# Add admins to sudo group
for admin in "${ADMIN_USERS[@]}"; do
    if id "$admin" &>/dev/null; then
        usermod -aG sudo "$admin"
        echo "  Added $admin to sudo group"
    fi
done

# Add regular users to 'users' group
for user in "${REGULAR_USERS[@]}"; do
    if id "$user" &>/dev/null; then
        usermod -aG users "$user"
        echo "  Added $user to users group"
    fi
done

# Remove unauthorized users from all groups
echo ""
echo "  Scanning for unauthorized group members..."
while IFS=: read -r groupname _ _ members; do
    if [[ -n "$members" ]]; then
        IFS=',' read -ra member_list <<< "$members"
        for member in "${member_list[@]}"; do
            member=$(echo "$member" | tr -d ' ')
            if [[ -n "$member" ]] && ! is_system_user "$member" && ! is_authorized "$member"; then
                echo "  Removing unauthorized '$member' from group '$groupname'"
                gpasswd -d "$member" "$groupname" 2>/dev/null
            fi
        done
    fi
done < /etc/group

# ============================================================
# TASK 6: Create "spider" group
#         Add may, peni, stan, miguel to it
#         Create new account "auntmay" and add to group
# ============================================================
echo ""
echo "=========================================="
echo "[TASK 6] Setting up Spider-Verse department..."
echo "=========================================="

# Create spider group if it doesn't exist
if ! getent group "$SPIDER_GROUP" &>/dev/null; then
    groupadd "$SPIDER_GROUP"
    echo "  Created group: $SPIDER_GROUP"
else
    echo "  Group $SPIDER_GROUP already exists."
fi

# Add existing authorized members to spider group
for member in "${SPIDER_MEMBERS[@]}"; do
    if id "$member" &>/dev/null; then
        usermod -aG "$SPIDER_GROUP" "$member"
        echo "  Added existing user '$member' to $SPIDER_GROUP"
    else
        echo "  WARNING: $member not found, skipping."
    fi
done

# Create new auntmay account and add to spider group
if ! id "$NEW_SPIDER_ACCOUNT" &>/dev/null; then
    useradd -m -s /bin/bash -G "$SPIDER_GROUP" "$NEW_SPIDER_ACCOUNT"
    echo "$NEW_SPIDER_ACCOUNT:ChangeMe123!" | chpasswd
    passwd -U "$NEW_SPIDER_ACCOUNT" 2>/dev/null
    echo "  Created new account: $NEW_SPIDER_ACCOUNT (added to $SPIDER_GROUP)"
else
    usermod -aG "$SPIDER_GROUP" "$NEW_SPIDER_ACCOUNT"
    echo "  $NEW_SPIDER_ACCOUNT already exists, added to $SPIDER_GROUP"
fi

# ============================================================
# TASK 7: Backup passwd, shadow, group files
# ============================================================
echo ""
echo "=========================================="
echo "[TASK 7] Backing up system files..."
echo "=========================================="

cp /etc/passwd ~/passwd_submission
cp /etc/shadow ~/shadow_submission
cp /etc/group ~/group_submission

echo "  Files saved to home directory:"
echo "    ~/passwd_submission"
echo "    ~/shadow_submission"
echo "    ~/group_submission"

echo ""
echo "=========================================="
echo "All tasks complete!"
echo ""
echo "Authorized Admins  : ${ADMIN_USERS[*]}"
echo "Authorized Users   : ${REGULAR_USERS[*]}"
echo "Spider Group       : ${SPIDER_MEMBERS[*]} + $NEW_SPIDER_ACCOUNT"
echo "=========================================="
