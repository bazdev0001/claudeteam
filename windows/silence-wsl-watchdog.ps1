# silence-wsl-watchdog.ps1 -- make the ApexFleet-WSL-Watchdog task fully invisible.
# The default task action launches powershell.exe directly; Task Scheduler flashes a
# console window briefly on every 10-min run even with -WindowStyle Hidden. This wraps
# the launch in wscript.exe (no console host), so nothing ever appears on screen.
# Run ONCE in PowerShell:  powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu\home\barry\projects\claudeteam\windows\silence-wsl-watchdog.ps1

$TASK_NAME = "ApexFleet-WSL-Watchdog"
$INSTALL_DIR = "C:\apexfleet"
$VBS = "$INSTALL_DIR\wsl-watchdog-hidden.vbs"

$task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "Task '$TASK_NAME' not found - nothing to silence. (Was install-wsl-watchdog.ps1 ever run?)"
    exit 0
}

# wait=True keeps wscript alive while powershell runs, so the task's 2-min
# ExecutionTimeLimit still kills the whole tree if the watchdog ever hangs.
@"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NonInteractive -ExecutionPolicy Bypass -File ""$INSTALL_DIR\wsl-watchdog.ps1""", 0, True
"@ | Set-Content -Path $VBS -Encoding ASCII

$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$VBS`""
Set-ScheduledTask -TaskName $TASK_NAME -Action $action | Out-Null
Write-Host "Done - '$TASK_NAME' now runs via wscript: fully invisible, same 10-min schedule, same 2-min hang-kill."
