# Version: 1.0.0
# ============================================================================
# REVERT-FFXI.ps1  —  undoes everything TUNE-FFXI applied
# Reads Revert\backup.json and restores every reg key, service startup,
# powercfg setting, and Defender exclusion to its pre-tune state.
# ============================================================================

$ErrorActionPreference = 'Continue'
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupPath = Join-Path $ScriptDir 'Revert\backup.json'
$LogPath    = Join-Path $ScriptDir 'REVERT-FFXI.log'

if (-not (Test-Path $BackupPath)) {
    Write-Host "No backup file at $BackupPath — nothing to revert." -ForegroundColor Yellow
    return
}

Start-Transcript -Path $LogPath -Append -Force | Out-Null

$B = Get-Content $BackupPath -Raw | ConvertFrom-Json
Write-Host "Reverting $($B.items.Count) items from backup dated $($B.ts)" -ForegroundColor Cyan

foreach ($it in $B.items) {
    try {
        switch ($it.kind) {
            'reg' {
                if ($null -eq $it.before) {
                    if (Test-Path $it.key) {
                        Remove-ItemProperty -Path $it.key -Name $it.value -Force -ErrorAction SilentlyContinue
                    }
                    Write-Host "  reg removed  $($it.key)\$($it.value)" -ForegroundColor Green
                } else {
                    if (-not (Test-Path $it.key)) { New-Item -Path $it.key -Force | Out-Null }
                    Set-ItemProperty -Path $it.key -Name $it.value -Value $it.before -Force
                    Write-Host "  reg restored $($it.key)\$($it.value) = $($it.before)" -ForegroundColor Green
                }
            }
            'defender' {
                try {
                    Remove-MpPreference -ExclusionPath $it.before -ErrorAction Stop
                    Write-Host "  defender: removed exclusion $($it.before)" -ForegroundColor Green
                } catch {
                    Write-Host "  defender skip: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            'service' {
                $st = if ([string]::IsNullOrWhiteSpace($it.before)) { 'Automatic' } else { $it.before }
                $mode = switch ($st) {
                    'Automatic'          { 'auto' }
                    'AutomaticDelayedStart' { 'delayed-auto' }
                    'Manual'             { 'demand' }
                    'Disabled'           { 'disabled' }
                    default              { 'auto' }
                }
                sc.exe config $it.value start= $mode | Out-Null
                Write-Host "  service: $($it.value) -> $st" -ForegroundColor Green
            }
            'powercfg' {
                if ($it.value -eq 'active') {
                    $m = [regex]::Match($it.before, '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
                    if ($m.Success) {
                        powercfg /setactive $m.Value | Out-Null
                        Write-Host "  powercfg: active plan restored ($($m.Value))" -ForegroundColor Green
                    }
                }
                elseif ($it.value -eq 'hibernate') {
                    powercfg /hibernate on
                    Write-Host "  powercfg: hibernate re-enabled" -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "  revert FAIL for $($it | ConvertTo-Json -Compress) : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Revert complete. Reboot to fully apply. ===" -ForegroundColor Cyan
Stop-Transcript | Out-Null
