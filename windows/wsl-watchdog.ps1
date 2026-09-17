# wsl-watchdog.ps1 -- restarts WSL if the distro goes offline
# Runs every 10 min via Task Scheduler. See windows/install-wsl-watchdog.ps1 to install.

$DISTRO   = "Ubuntu"
$LOG      = "C:\apexfleet\watchdog.log"
$MAX_LOG  = 500  # lines to keep (trim on each run)

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LOG -Value "$ts $msg"
}

# Trim log
if (Test-Path $LOG) {
    $lines = Get-Content $LOG
    if ($lines.Count -gt $MAX_LOG) {
        $lines | Select-Object -Last $MAX_LOG | Set-Content $LOG
    }
}

$running = & wsl --list --running 2>&1
$isUp = ($running -join "") -replace '\x00','' -match [regex]::Escape($DISTRO)

if ($isUp) {
    exit 0  # healthy -- no log spam
}

Log "WSL distro '$DISTRO' not running -- starting..."
& wsl -d $DISTRO -- bash -c "echo wsl-watchdog-restart >> /tmp/wsl-watchdog.log" 2>&1 | Out-Null
Start-Sleep -Seconds 15

$running2 = & wsl --list --running 2>&1
if (($running2 -join "") -replace '\x00','' -match [regex]::Escape($DISTRO)) {
    Log "WSL '$DISTRO' back up OK"
} else {
    Log "WSL '$DISTRO' FAILED to start -- check Windows Event Log"
}
