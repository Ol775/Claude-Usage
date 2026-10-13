<#
.SYNOPSIS
  Copies Claude Code's usage logs from this Windows PC into a folder that syncs to your Mac (iCloud Drive, OneDrive, a shared folder).
  On the Mac, add that folder in Claude Usage: Settings > Data > Other computers.

.EXAMPLE
  .\Sync-ClaudeLogs.ps1                                                                   # asks for the folder
  .\Sync-ClaudeLogs.ps1 -Destination "$env:USERPROFILE\iCloudDrive\ClaudeLogs"             # copy once
  .\Sync-ClaudeLogs.ps1 -Destination "$env:USERPROFILE\iCloudDrive\ClaudeLogs" -Install    # copy now, then every 5 minutes (change with -IntervalMinutes)
  .\Sync-ClaudeLogs.ps1 -Uninstall                                                         # stop the scheduled copy

.NOTES
  Only *.jsonl files from the last year are copied, and nothing is ever deleted or changed in Claude Code's own folder.
  The logs contain your Claude Code conversations, so whatever syncs the destination folder uploads them. Pick a service you trust.
  Keep this script where it is after -Install: the scheduled task runs it from here.
#>
param(
    [string]$Destination,
    [string]$Source = (Join-Path $env:USERPROFILE ".claude\projects"),
    [int]$IntervalMinutes = 5,
    [switch]$Install,
    [switch]$Uninstall
)
$ErrorActionPreference = "Stop"
$TaskName = "Claude Usage log sync"

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Scheduled copy removed. Copied logs stay where they are."
    return
}
if (-not $Destination) {
    $Destination = (Read-Host "Folder that syncs to your Mac (e.g. C:\Users\you\iCloudDrive\ClaudeLogs)").Trim().Trim('"')
    if (-not $Destination) { throw "No folder given." }
    if (-not $Install) { $Install = (Read-Host "Also copy every $IntervalMinutes minutes in the background? (y/N)") -match '^[yY]' }
}
if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Claude Code logs not found at $Source (use -Source if they live elsewhere)." }

$src = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\', '/')
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$dst = (Resolve-Path -LiteralPath $Destination).Path
$oldest = (Get-Date).AddDays(-365)
$copied = 0
Get-ChildItem -LiteralPath $src -Recurse -Filter *.jsonl -File | Where-Object { $_.LastWriteTime -ge $oldest } | ForEach-Object {
    $target = Join-Path $dst $_.FullName.Substring($src.Length).TrimStart('\', '/')
    $t = Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
    if ($t -and $t.Length -eq $_.Length -and $t.LastWriteTimeUtc -eq $_.LastWriteTimeUtc) { return }     # unchanged
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force      # Copy-Item keeps the modified time, so the check above works
    $copied++
}
Write-Host "Copied $copied changed log file(s) to $dst"

if ($Install) {
    $self = $MyInvocation.MyCommand.Path
    $taskArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Destination `"$dst`" -Source `"$src`""
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host "Scheduled: copies every $IntervalMinutes minutes while you're signed in. Remove with -Uninstall."
}
