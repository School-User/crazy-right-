import os
import platform
import subprocess
import datetime
from pathlib import Path

# Configuration Constants
DAYS_LOOKBACK = 180
RESULT_LIMIT = 200
DESKTOP = Path.home() / "Desktop"
TIMESTAMP = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
OUTPUT_FILE = DESKTOP / f"universal_audit_{TIMESTAMP}.txt"

def get_recent_files(scan_path, days=DAYS_LOOKBACK, limit=RESULT_LIMIT):
    """Finds files modified in the last X days, sorted by newest first."""
    files_list = []
    cutoff = datetime.datetime.now() - datetime.timedelta(days=days)
    
    try:
        # Scan up to 3 levels deep to capture hidden configs
        for root, dirs, files in os.walk(scan_path):
            depth = root.count(os.sep) - str(scan_path).count(os.sep)
            if depth >= 3:
                del dirs[:] # Stop deeper recursion
                continue
                
            for name in files:
                f_path = Path(root) / name
                try:
                    mtime = datetime.datetime.fromtimestamp(f_path.stat().st_mtime)
                    if mtime > cutoff:
                        files_list.append((mtime, f_path))
                except (PermissionError, OSError):
                    continue
    except Exception:
        pass

    # Sort by date descending (newest first)
    files_list.sort(key=lambda x: x[0], reverse=True)
    return [f"{t.strftime('%b %d %H:%M')} -> {p}" for t, p in files_list[:limit]]

def run_audit():
    system = platform.system()
    report = []
    report.append("==========================================")
    report.append(f"       SYSTEM AUDIT ({system})")
    report.append(f"       Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    report.append("==========================================\n")

    # 1. OS & Kernel Information
    report.append("--- OS INFORMATION ---")
    report.append(f"System: {platform.system()} {platform.release()}")
    report.append(f"Version: {platform.version()}\n")

    # 2. OS-Specific Logic
    if system == "Windows":
        # Apps via PowerShell Registry query
        try:
            apps_cmd = "Get-ItemProperty HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\* | Select-Object -ExpandProperty DisplayName"
            apps = subprocess.check_output(["powershell", "-Command", apps_cmd], stderr=subprocess.DEVNULL, shell=True).decode().splitlines()
            report.append("--- INSTALLED APPLICATIONS ---\n" + "\n".join(sorted(set(filter(None, apps)))) + "\n")
        except:
            report.append("--- INSTALLED APPLICATIONS ---\nCould not retrieve app list.\n")
        
        # Registry Changes (150 results)
        report.append("--- RECENT SYSTEM REGISTRY KEY CHANGES (180 Days) ---")
        reg_cmd = f"$days = (Get-Date).AddDays(-{DAYS_LOOKBACK}); Get-ChildItem -Path HKLM:\\System, HKLM:\\Software -Recurse -ErrorAction SilentlyContinue | Where-Object {{ (Get-Item $_.PSPath).LastWriteTime -ge $days }} | Sort-Object LastWriteTime -Descending | Select-Object -First 150 | ForEach-Object {{ $w = (Get-Item $_.PSPath).LastWriteTime; '{{0:MMM dd HH:mm}} -> {{1}}' -f $w, $_.Name }}"
        try:
            reg_changes = subprocess.check_output(["powershell", "-Command", reg_cmd], shell=True).decode().splitlines()
            report.extend(reg_changes if reg_changes else ["No recent registry changes found."])
        except:
            report.append("Error querying registry.")
        report.append("")

        # Global Configs
        report.append("--- GLOBAL CONFIGS (ProgramData - Last 180 Days) ---")
        report.extend(get_recent_files(os.environ.get('ProgramData', 'C:\\ProgramData')))
        
        # User Configs
        report.append("\n--- USER CONFIGS (AppData - Last 180 Days) ---")
        report.extend(get_recent_files(os.environ.get('AppData', '')))

    else: # Linux logic
        # Desktop Environment
        report.append(f"Desktop Environment: {os.environ.get('XDG_CURRENT_DESKTOP', 'Unknown')}\n")
        
        # Apps
        try:
            apps = subprocess.check_output("ls /usr/share/applications/*.desktop 2>/dev/null | xargs -n 1 basename | sed 's/.desktop//'", shell=True).decode().splitlines()
            report.append("--- INSTALLED APPLICATIONS ---\n" + "\n".join(sorted(apps)) + "\n")
        except:
            report.append("--- INSTALLED APPLICATIONS ---\nCould not retrieve app list.\n")
        
        # Global Configs
        report.append("--- GLOBAL CONFIGS (/etc - Last 180 Days) ---")
        report.extend(get_recent_files("/etc"))
        
        # User Configs
        report.append("\n--- USER CONFIGS (Home - Last 180 Days) ---")
        report.extend(get_recent_files(Path.home()))

    # Final Output to File
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(report))
    
    print(f"Audit complete! Your report is here: {OUTPUT_FILE}")

if __name__ == "__main__":
    run_audit()
