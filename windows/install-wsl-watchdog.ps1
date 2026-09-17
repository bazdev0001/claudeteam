# install-wsl-watchdog.ps1 -- one-time setup for the WSL watchdog Task Scheduler job
# Run this ONCE from PowerShell (no admin needed for current-user tasks).
# Re-run to update the task after editing wsl-watchdog.ps1.

$TASK_NAME  = "ApexFleet-WSL-Watchdog"
$INSTALL_DIR = "C:\apexfleet"
$SCRIPT      = "$INSTALL_DIR\wsl-watchdog.ps1"
$SOURCE      = "$PSScriptRoot\wsl-watchdog.ps1"

# Copy watchdog script to a stable Windows path (UNC paths are unreliable in Task Scheduler)
if (-not (Test-Path $INSTALL_DIR)) { New-Item -ItemType Directory -Path $INSTALL_DIR | Out-Null }
Copy-Item -Path $SOURCE -Destination $SCRIPT -Force
Write-Host "Copied watchdog to $SCRIPT"

# Remove old task if exists
Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue
# Naming consolidation 2026-07-17: retire the legacy ClaudeTeam task + dir on first apexfleet install
Unregister-ScheduledTask -TaskName "ClaudeTeam-WSL-Watchdog" -Confirm:$false -ErrorAction SilentlyContinue
if (Test-Path "C:\claudeteam") { Remove-Item -Recurse -Force "C:\claudeteam" -ErrorAction SilentlyContinue }

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SCRIPT`""

# Trigger 1: at logon (with 2-min delay for WSL to settle)
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn
$triggerLogon.Delay = "PT2M"

# Trigger 2: repeat every 10 minutes (27-year duration; [TimeSpan]::MaxValue makes invalid task XML)
$triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 10) `
    -RepetitionDuration (New-TimeSpan -Days 9999)

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
    -StartWhenAvailable `
    -DontStopIfGoingOnBatteries `
    -RunOnlyIfNetworkAvailable:$false

Register-ScheduledTask `
    -TaskName $TASK_NAME `
    -Action $action `
    -Trigger @($triggerLogon, $triggerRepeat) `
    -Settings $settings `
    -RunLevel Limited `
    -Description "Restarts WSL Ubuntu if it goes offline, keeping the ClaudeTeam fleet alive." | Out-Null

Write-Host "Task '$TASK_NAME' registered. Runs at logon + every 10 min."
Write-Host "Log: C:\apexfleet\watchdog.log"
Write-Host "Test now: Start-ScheduledTask -TaskName '$TASK_NAME'"
