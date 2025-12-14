@echo off
setlocal EnableDelayedExpansion
title CyberPatriot Vulnerability Fixer
color 0A

:: Check for Administrator privileges
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo This script requires Administrator privileges.
    echo Please right-click and select "Run as Administrator".
    pause
    exit /b
)

echo ========================================================
echo      STARTING CYBERPATRIOT HARDENING SCRIPT
echo ========================================================
echo.

:: ----------------------------------------------------------
:: 1. AUDIT POLICY
:: ----------------------------------------------------------
echo [+] Configuring Audit Policies...
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
echo.

:: ----------------------------------------------------------
:: 2. LOCAL POLICY - SECURITY OPTIONS (Via Registry)
:: ----------------------------------------------------------
echo [+] Configuring Security Options...

:: Item 2 & 3: Admin/Guest Account Status (Handled in User section)

:: Item 4: Restrict CD-ROM access to locally logged-on user only (Enabled)
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AllocateCDRoms /t REG_SZ /d 1 /f

:: Item 5: Do not display last user name (Enabled)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v dontdisplaylastusername /t REG_DWORD /d 1 /f

:: Item 6: Do not require CTRL+ALT+DEL (Disabled - meaning we REQUIRE it)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableCAD /t REG_DWORD /d 0 /f

:: Item 7: Do not allow anonymous enumeration of SAM accounts (Enabled)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RestrictAnonymousSAM /t REG_DWORD /d 1 /f

:: Item 8: Recovery console: Allow automatic administrative logon (Disabled)
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole" /v SecurityLevel /t REG_DWORD /d 0 /f

:: Item 9: UAC: Switch to the secure desktop (Enabled)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v PromptOnSecureDesktop /t REG_DWORD /d 1 /f

echo.

:: ----------------------------------------------------------
:: 3. ACCOUNT POLICIES
:: ----------------------------------------------------------
echo [+] Configuring Account Policies...

:: Item 12: Account lockout threshold (5 attempts)
net accounts /lockoutthreshold:5

:: Item 13: Enforce password history (5 passwords)
:: Item 14: Max password age (90 days)
:: Item 15: Minimum password length (REMOVED per request)
net accounts /uniquepw:5 /maxpwage:90

:: Item 16 & 17: Complexity and Reversible Encryption
:: Note: 'net accounts' cannot set complexity. We use a temp cfg file with secedit.
echo [System Access] > temp_policy.cfg
echo PasswordComplexity = 1 >> temp_policy.cfg
echo ClearTextPassword = 0 >> temp_policy.cfg
echo [+] Applying Password Complexity and Encryption settings...
secedit /configure /db secedit.sdb /cfg temp_policy.cfg /areas SECURITYPOLICY /quiet
del temp_policy.cfg

echo.

:: ----------------------------------------------------------
:: 4. USERS AND GROUPS
:: ----------------------------------------------------------
echo [+] Configuring Users and Groups...

:: Item 2: Administrator (Disabled)
net user Administrator /active:no

:: Item 3: Guest (Disabled)
net user Guest /active:no

:: Item 20, 21: batman
net user batman /logonpasswordchg:yes
wmic useraccount where name='batman' set passwordexpires=true

:: Item 22: flash
net user flash /passwordchg:yes

:: Item 23: green lantern
net user "green lantern" /logonpasswordchg:yes

:: Item 24: joker
net user joker /active:no

:: Item 25: lex luther
net user "lex luther" /active:no

:: Item 26: wonder woman
net user "wonder woman" /active:yes

:: Item 27: Administrators Group (Adding superman and wonder woman)
net localgroup Administrators superman /add
net localgroup Administrators "wonder woman" /add

:: Item 28: Justice League Group
:: Note: Assuming group exists. If not, script will error on add, which is fine.
net localgroup "Justice League" aquaman /add
net localgroup "Justice League" batman /add
net localgroup "Justice League" flash /add
net localgroup "Justice League" "wonder woman" /add
net localgroup "Justice League" superman /add

echo.

:: ----------------------------------------------------------
:: 5. FIREWALL PROFILES
:: ----------------------------------------------------------
echo [+] Configuring Firewall...
:: Items 32-37: Turn On and Block Inbound for all profiles
netsh advfirewall set allprofiles state on
netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound
echo.

:: ----------------------------------------------------------
:: 6. SHARES
:: ----------------------------------------------------------
echo [+] Removing Shares...
:: Item 30: Stop sharing C (Usually implies a custom share named C, not C$)
net share C /delete
:: Just in case it refers to the admin share (use caution)
:: net share C$ /delete 
echo.

:: ----------------------------------------------------------
:: 7. AUTOMATIC UPDATES
:: ----------------------------------------------------------
echo [+] Enabling Automatic Updates...
:: Item 31
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /t REG_DWORD /d 4 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 0 /f
echo.

:: ----------------------------------------------------------
:: 8. SERVICES
:: ----------------------------------------------------------
echo [+] Disabling Vulnerable Services...
:: Item 38: Offline Files
sc stop CscService
sc config CscService start= disabled

:: Item 39: Print Spooler
sc stop Spooler
sc config Spooler start= disabled
echo.

:: ----------------------------------------------------------
:: 9. ROLES AND FEATURES
:: ----------------------------------------------------------
echo [+] Disabling Features...
:: Item 40: Telnet Client
dism /online /disable-feature /featurename:TelnetClient
echo.

:: ----------------------------------------------------------
:: 10. REMOVE FILES
:: ----------------------------------------------------------
echo [+] Removing Prohibited Files...

:: Item 41
if exist "C:\Users\aquaman\Desktop\my_passwords.txt" del /f /q "C:\Users\aquaman\Desktop\my_passwords.txt"

:: Item 42
if exist "C:\Users\flash\Downloads\MinecraftInstaller.msi" del /f /q "C:\Users\flash\Downloads\MinecraftInstaller.msi"

:: Item 43
if exist "C:\Users\wonder woman\Pictures\decoder.gif" del /f /q "C:\Users\wonder woman\Pictures\decoder.gif"

:: Item 44
if exist "C:\Windows\file-pro.txt" del /f /q "C:\Windows\file-pro.txt"

:: Item 45
if exist "C:\ProgramData\win-mode.bat" del /f /q "C:\ProgramData\win-mode.bat"

:: Item 46
if exist "C:\Users\Captain America\john180j1w.zip" del /f /q "C:\Users\Captain America\john180j1w.zip"
echo.

:: ----------------------------------------------------------
:: 11. UNINSTALL PROGRAMS
:: ----------------------------------------------------------
echo [+] Attempting to uninstall prohibited software...
echo     (Note: If this fails, please uninstall via Control Panel manually)

:: Item 18: WinPcap
wmic product where "name like 'WinPcap%%'" call uninstall /nointeractive

:: Item 19: Wireshark
wmic product where "name like 'Wireshark%%'" call uninstall /nointeractive

echo.
echo ========================================================
echo      SCRIPT COMPLETE
echo ========================================================
echo Please verify specific User Rights Assignments manually (Items 10, 11).
echo Please verify software uninstalls in Control Panel.
pause
