@echo off
setlocal
:: =============================================================================
:: PROJECT: AuditTrail-Win-Registry (v2.0)
:: AUTHOR:  CyberPatriot Open Source Collective
:: PURPOSE: Windows Forensic Audit (Files, Logs, + DEEP REGISTRY SCAN)
:: =============================================================================

:: --- 1. Admin & Environment Check ---
fltmc >nul 2>&1 || (
    echo [!] CRITICAL: Admin rights required for Registry access.
    echo     Right-click this file -> "Run as Administrator"
    pause
    exit /b
)

:: Set Output Path (User Desktop)
set "REPORT_FILE=%USERPROFILE%\Desktop\AuditTrail_Report_%COMPUTERNAME%_%date:~-4,4%%date:~-10,2%%date:~-7,2%.txt"

cls
echo ==========================================================
echo        AuditTrail-180 | Windows Forensic Engine
echo ==========================================================
echo [*] Target:       %COMPUTERNAME%
echo [*] User Context: %USERNAME%
echo [*] Lookback:     180 Days
echo [*] Scanning Registry Hives (HKLM/HKCU)...
echo.

:: --- 2. PowerShell Forensic Engine ---
:: We embed the PowerShell logic here to keep it as a single file tool.
:: It calculates dates, scans specific registry hives, and checks file mtimes.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& {" ^
    "$ErrorActionPreference = 'SilentlyContinue';" ^
    "$cutoff = (Get-Date).AddDays(-180);" ^
    "$report = @();" ^
    "" ^
    "function Log-Section($title) {" ^
    "    Write-Host \"[*] Scanning: $title...\" -ForegroundColor Cyan;" ^
    "    $global:report += \"`n========================================\";" ^
    "    $global:report += \"$title\";" ^
    "    $global:report += \"========================================\";" ^
    "}" ^
    "" ^
    "Log-Section '1. SYSTEM ENVIRONMENT';" ^
    "$os = Get-CimInstance Win32_OperatingSystem;" ^
    "$global:report += \"Hostname:    $($env:COMPUTERNAME)\";" ^
    "$global:report += \"OS Version:  $($os.Caption) ($($os.Version))\";" ^
    "$global:report += \"Last Boot:   $($os.LastBootUpTime)\";" ^
    "$global:report += \"Arch:        $($os.OSArchitecture)\";" ^
    "" ^
    "Log-Section '2. REGISTRY: INSTALLED SOFTWARE (Last 180 Days)';" ^
    "$locs = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*');" ^
    "Get-ItemProperty $locs | Where-Object { $_.InstallDate } | ForEach-Object {" ^
    "    try {" ^
    "        $d = [DateTime]::ParseExact($_.InstallDate, 'yyyyMMdd', $null);" ^
    "        if ($d -gt $cutoff) {" ^
    "            $global:report += \"[$($d.ToString('yyyy-MM-dd'))] $($_.DisplayName) ($($_.DisplayVersion))\"" ^
    "        }" ^
    "    } catch {}" ^
    "} | Sort-Object;" ^
    "" ^
    "Log-Section '3. REGISTRY: PERSISTENCE (Startup Keys)';" ^
    "$global:report += \"[!] These items auto-start with Windows (Check for unauthorized scripts)\";" ^
    "$runKeys = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce');" ^
    "foreach ($key in $runKeys) {" ^
    "    $global:report += \"`n--- Key: $key ---\";" ^
    "    Get-ItemProperty $key | Get-Member -MemberType NoteProperty | ForEach-Object {" ^
    "        $val = (Get-ItemProperty $key).($_.Name);" ^
    "        $global:report += \"   [ENTRY] $($_.Name) -> $val\"" ^
    "    }" ^
    "}" ^
    "" ^
    "Log-Section '4. REGISTRY: SECURITY CONFIG (UAC & Policies)';" ^
    "$uac = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System';" ^
    "$global:report += \"EnableLUA (UAC):      $($uac.EnableLUA) (1=On, 0=Off/Danger)\";" ^
    "$global:report += \"ConsentPromptBehavior: $($uac.ConsentPromptBehaviorAdmin)\";" ^
    "$global:report += \"RemoteDesktop (fDeny): $((Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections)\";" ^
    "" ^
    "Log-Section '5. MODIFIED EXECUTABLES (Program Files - Top 25)';" ^
    "Get-ChildItem -Path $env:ProgramFiles, ${env:ProgramFiles(x86)} -Recurse -File -Include *.exe,*.dll,*.bat,*.ps1 -ErrorAction SilentlyContinue | " ^
    "Where-Object { $_.LastWriteTime -gt $cutoff } | " ^
    "Sort-Object LastWriteTime -Descending | Select-Object -First 25 | " ^
    "ForEach-Object { $global:report += \"[$($_.LastWriteTime)] $($_.FullName)\" };" ^
    "" ^
    "Log-Section '6. RECENT SERVICE INSTALLS (Event ID 7045)';" ^
    "Get-WinEvent -FilterHashtable @{LogName='System'; Id=7045; StartTime=$cutoff} -ErrorAction SilentlyContinue | " ^
    "Select-Object -First 15 | ForEach-Object {" ^
    "    $msg = $_.Properties[0].Value -replace 'File Name:',' -> Path:';" ^
    "    $global:report += \"[$($_.TimeCreated)] $msg\"" ^
    "};" ^
    "" ^
    "$global:report | Out-File -FilePath '%REPORT_FILE%' -Encoding UTF8;" ^
    "}"

echo.
if exist "%REPORT_FILE%" (
    echo [SUCCESS] Forensics Complete.
    echo Report saved to: "%REPORT_FILE%"
) else (
    echo [!] Error: Report generation failed.
)
echo.
pause
