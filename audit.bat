@echo off
setlocal enabledelayedexpansion

:: Define output file on Desktop
set "OUTPUT=%USERPROFILE%\Desktop\windows_audit_%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%.txt"
set "OUTPUT=%OUTPUT: =0%"

{
echo ==========================================
echo        WINDOWS SYSTEM AUDIT (.BAT)         
echo        Generated: %date% %time%            
echo ==========================================
echo.

echo --- OS INFORMATION ---
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" /C:"System Type"
echo.

echo --- INSTALLED APPLICATIONS ---
powershell -Command "Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName | Sort-Object DisplayName"
echo.

echo --- GLOBAL CONFIG CHANGES (ProgramData - Last 180 Days) ---
powershell -Command "Get-ChildItem -Path $env:ProgramData -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-180) } | Sort-Object LastWriteTime -Descending | Select-Object -First 200 | ForEach-Object { '{0:MMM dd HH:mm} -> {1}' -f $_.LastWriteTime, $_.FullName }"
echo.

echo --- USER CONFIG CHANGES (AppData - Last 180 Days) ---
powershell -Command "Get-ChildItem -Path $env:AppData -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-180) } | Sort-Object LastWriteTime -Descending | Select-Object -First 200 | ForEach-Object { '{0:MMM dd HH:mm} -> {1}' -f $_.LastWriteTime, $_.FullName }"
echo.

echo --- RECENT SYSTEM REGISTRY KEY CHANGES (Last 180 Days) ---
:: Note: Registry 'LastWriteTime' is accessible via PowerShell for keys (not individual values)
powershell -Command "$days = (Get-Date).AddDays(-180); Get-ChildItem -Path HKLM:\System, HKLM:\Software -Recurse -ErrorAction SilentlyContinue | Where-Object { (Get-Item $_.PSPath).LastWriteTime -ge $days } | Sort-Object LastWriteTime -Descending | Select-Object -First 150 | ForEach-Object { $writeTime = (Get-Item $_.PSPath).LastWriteTime; '{0:MMM dd HH:mm} -> {1}' -f $writeTime, $_.Name }"

} > "%OUTPUT%"

echo Audit complete! Report saved to Desktop.
pause
