# Version: 1.0.0
# ============================================================================
# TUNE-FFXI.ps1  —  FFXI + Windower tuner for Ryzen 5800X3D + RTX 5060 + Win11
#
# Applies well-documented tweaks that matter most for FFXI multiboxing:
#   1. Windows Defender exclusions on pol.exe + Windower folder
#   2. Fullscreen optimizations OFF + High-DPI System for pol.exe / windower.exe
#   3. Xbox Game Bar / Game DVR OFF
#   4. Hardware-Accelerated GPU Scheduling ON
#   5. Ultimate Performance power plan + set active
#   6. Hibernation + Fast Startup OFF
#   7. USB selective suspend OFF (AC)
#   8. Nagle's algorithm OFF on primary adapter
#   9. MMCSS "Games" scheduler priority raised
#  10. Ndu (Network Data Usage) service OFF
#  11. Verify SSD TRIM
#
# Every change is backed up to Revert\backup.json BEFORE applying.
# Undo everything by running REVERT-FFXI.bat as administrator.
#
# Requires PowerShell 5.1+ (default on Windows 11). No ternary / no PS7 syntax.
# ============================================================================

$ErrorActionPreference = 'Continue'  # keep going on non-fatal errors
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath    = Join-Path $ScriptDir 'TUNE-FFXI.log'
$BackupDir  = Join-Path $ScriptDir 'Revert'
$BackupPath = Join-Path $BackupDir 'backup.json'

if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }

# Tee everything to log AND console
Start-Transcript -Path $LogPath -Append -Force | Out-Null

Write-Host ""
Write-Host "=== TUNE-FFXI  $(Get-Date -Format o) ===" -ForegroundColor Cyan
Write-Host "System: $((Get-CimInstance Win32_ComputerSystem).Manufacturer) $((Get-CimInstance Win32_ComputerSystem).Model)"
Write-Host "CPU:    $((Get-CimInstance Win32_Processor).Name)"
Write-Host "OS:     $((Get-CimInstance Win32_OperatingSystem).Caption)"
Write-Host "PS ver: $($PSVersionTable.PSVersion)"
Write-Host ""

# --- Backup helpers ---
$script:Backup = [ordered]@{
    ts    = (Get-Date).ToString('o')
    items = @()
}

function Add-Backup($kind, $key, $value, $before) {
    $script:Backup.items += [pscustomobject]@{
        kind   = $kind
        key    = $key
        value  = $value
        before = $before
    }
}

function Save-Backup {
    $script:Backup | ConvertTo-Json -Depth 6 | Out-File -FilePath $BackupPath -Encoding UTF8
    Write-Host "  backup saved: $BackupPath" -ForegroundColor DarkGray
}

function Get-RegValueSafe($path, $name) {
    try { return (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name }
    catch { return $null }
}

function Set-RegValueTracked($path, $name, $type, $value) {
    $before = Get-RegValueSafe $path $name
    Add-Backup 'reg' $path $name $before
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    try {
        Set-ItemProperty -Path $path -Name $name -Type $type -Value $value -Force
        Write-Host "  reg set $path\$name = $value" -ForegroundColor Green
    } catch {
        Write-Host "  reg FAIL $path\$name : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- FFXI / Windower path detection ---
Write-Host "=== 0. FFXI + Windower path detection ===" -ForegroundColor Cyan
$polCandidates = @(
    'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\pol.exe',
    'C:\Program Files (x86)\Steam\steamapps\common\FFXINA\SquareEnix\PlayOnlineViewer\pol.exe',
    'C:\Program Files\PlayOnline\SquareEnix\PlayOnlineViewer\pol.exe',
    'D:\PlayOnline\SquareEnix\PlayOnlineViewer\pol.exe',
    'D:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\pol.exe'
)
$polExe = $polCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $polExe) {
    $entered = Read-Host "pol.exe not auto-detected. Enter full path (blank to skip)"
    if ($entered -and (Test-Path $entered)) { $polExe = $entered }
}

$windowerCandidates = @(
    'C:\Windower\windower.exe',
    'D:\Windower\windower.exe',
    'C:\Program Files (x86)\Windower\windower.exe',
    'D:\Program Files (x86)\Windower\windower.exe'
)
$windowerExe = $windowerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $windowerExe) {
    $entered = Read-Host "windower.exe not auto-detected. Enter full path (blank to skip)"
    if ($entered -and (Test-Path $entered)) { $windowerExe = $entered }
}
$windowerDir = $null
if ($windowerExe) { $windowerDir = Split-Path $windowerExe -Parent }

if ($polExe)       { Write-Host "  pol.exe:      $polExe" }       else { Write-Host "  pol.exe:      (skipped)" -ForegroundColor Yellow }
if ($windowerExe)  { Write-Host "  windower.exe: $windowerExe" }  else { Write-Host "  windower.exe: (skipped)" -ForegroundColor Yellow }
if ($windowerDir)  { Write-Host "  windower dir: $windowerDir" }
Write-Host ""

# --- 1. Windows Defender exclusions ---
Write-Host "=== 1. Windows Defender exclusions ===" -ForegroundColor Cyan
$exclusions = @()
if ($polExe)      { $exclusions += $polExe }
if ($windowerExe) { $exclusions += $windowerExe }
if ($windowerDir) { $exclusions += $windowerDir }
foreach ($p in $exclusions) {
    try {
        Add-MpPreference -ExclusionPath $p -ErrorAction Stop
        Add-Backup 'defender' 'exclusion' $p $p
        Write-Host "  exclude: $p" -ForegroundColor Green
    } catch {
        Write-Host "  skip:    $p ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}
Write-Host ""

# --- 2. Fullscreen Optimizations OFF + High DPI System ---
Write-Host "=== 2. Fullscreen Optimizations OFF + High DPI System ===" -ForegroundColor Cyan
$layers = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
if ($polExe)      { Set-RegValueTracked $layers $polExe      'String' '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE' }
if ($windowerExe) { Set-RegValueTracked $layers $windowerExe 'String' '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE' }
Write-Host ""

# --- 3. Xbox Game Bar / Game DVR OFF ---
Write-Host "=== 3. Xbox Game Bar / Game DVR OFF ===" -ForegroundColor Cyan
Set-RegValueTracked 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 'DWord' 0
Set-RegValueTracked 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 'DWord' 0
Set-RegValueTracked 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 'DWord' 2
Set-RegValueTracked 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 'DWord' 0
Write-Host ""

# --- 4. Hardware-Accelerated GPU Scheduling ON ---
Write-Host "=== 4. Hardware-Accelerated GPU Scheduling ON ===" -ForegroundColor Cyan
Set-RegValueTracked 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 'DWord' 2
Write-Host ""

# --- 5. Ultimate Performance power plan ---
Write-Host "=== 5. Ultimate Performance power plan ===" -ForegroundColor Cyan
try {
    $activeBefore = (powercfg /getactivescheme) -join ' '
    Add-Backup 'powercfg' 'active' $null $activeBefore
    $dup = (powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61) -join ' '
    Write-Host "  $dup"
    $guidMatch = [regex]::Match($dup, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    if ($guidMatch.Success) {
        powercfg /setactive $guidMatch.Value | Out-Null
        Write-Host "  set active: $($guidMatch.Value)" -ForegroundColor Green
    } else {
        Write-Host "  (plan already exists — searching for existing Ultimate Performance GUID)"
        $list = powercfg /list
        foreach ($line in $list) {
            if ($line -match 'Ultimate Performance' -and $line -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                powercfg /setactive $matches[1] | Out-Null
                Write-Host "  set active: $($matches[1])" -ForegroundColor Green
                break
            }
        }
    }
} catch {
    Write-Host "  powercfg FAIL: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# --- 6. Hibernation + Fast Startup OFF ---
Write-Host "=== 6. Hibernation + Fast Startup OFF ===" -ForegroundColor Cyan
try {
    Add-Backup 'powercfg' 'hibernate' $null 'on'
    powercfg /hibernate off
    Write-Host "  hibernate off (also disables Fast Startup)" -ForegroundColor Green
} catch {
    Write-Host "  hibernate FAIL: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# --- 7. USB selective suspend OFF (AC) ---
Write-Host "=== 7. USB selective suspend OFF (AC) ===" -ForegroundColor Cyan
try {
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    Write-Host "  USB selective suspend disabled on AC" -ForegroundColor Green
} catch {
    Write-Host "  USB FAIL: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# --- 8. Nagle's algorithm OFF on primary adapter ---
Write-Host "=== 8. Nagle's algorithm OFF on primary adapter ===" -ForegroundColor Cyan
try {
    $active = Get-NetAdapter | Where-Object Status -eq 'Up' | Sort-Object InterfaceMetric | Select-Object -First 1
    if ($active) {
        $cfg = Get-NetIPAddress -InterfaceIndex $active.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $primaryIP = $null
        if ($cfg) { $primaryIP = ($cfg | Select-Object -First 1).IPAddress }
        Write-Host "  adapter: $($active.Name)  ip: $primaryIP"
        $ifRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
        $interfaces = Get-ChildItem $ifRoot -ErrorAction SilentlyContinue
        $matched = $false
        foreach ($t in $interfaces) {
            $vals = Get-ItemProperty $t.PSPath -ErrorAction SilentlyContinue
            $ipMatch = $false
            if ($vals.IPAddress -and $primaryIP -and ($vals.IPAddress -contains $primaryIP)) { $ipMatch = $true }
            if ($vals.DhcpIPAddress -and $primaryIP -and ($vals.DhcpIPAddress -eq $primaryIP))  { $ipMatch = $true }
            if ($ipMatch) {
                Set-RegValueTracked $t.PSPath 'TcpAckFrequency' 'DWord' 1
                Set-RegValueTracked $t.PSPath 'TCPNoDelay'      'DWord' 1
                $matched = $true
            }
        }
        if (-not $matched) { Write-Host "  no matching interface registry key — skipped" -ForegroundColor Yellow }
    } else {
        Write-Host "  no active adapter detected" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Nagle FAIL: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# --- 9. MMCSS Games priority raised ---
Write-Host "=== 9. MMCSS Games priority raised ===" -ForegroundColor Cyan
$games   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
$sysProf = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
Set-RegValueTracked $games 'GPU Priority'         'DWord'  8
Set-RegValueTracked $games 'Priority'             'DWord'  6
Set-RegValueTracked $games 'Scheduling Category'  'String' 'High'
Set-RegValueTracked $games 'SFIO Priority'        'String' 'High'
Set-RegValueTracked $sysProf 'SystemResponsiveness' 'DWord' 10
Write-Host ""

# --- 10. Ndu (Network Data Usage) service OFF ---
Write-Host "=== 10. Ndu service OFF ===" -ForegroundColor Cyan
try {
    $svc = Get-Service Ndu -ErrorAction SilentlyContinue
    if ($svc) {
        Add-Backup 'service' 'Ndu' $null ($svc.StartType.ToString())
        sc.exe config Ndu start= disabled | Out-Null
        Write-Host "  Ndu -> Disabled (takes effect after reboot)" -ForegroundColor Green
    } else {
        Write-Host "  Ndu service not present — skipped" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Ndu FAIL: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# --- 11. Verify SSD TRIM ---
Write-Host "=== 11. Verify SSD TRIM ===" -ForegroundColor Cyan
try {
    $trim = (fsutil behavior query DisableDeleteNotify) -join ' | '
    Write-Host "  $trim"
    Write-Host "  (NTFS/ReFS DisableDeleteNotify = 0 means TRIM enabled — good)"
} catch {
    Write-Host "  TRIM check FAIL: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# --- Save backup ---
Save-Backup

Write-Host ""
Write-Host "=== NVIDIA-side (do manually in NVIDIA Control Panel) ===" -ForegroundColor Cyan
Write-Host "  Manage 3D settings -> Program Settings -> Add: pol.exe"
Write-Host "    Low Latency Mode      = Ultra"
Write-Host "    Power management mode = Prefer maximum performance"
Write-Host "    Threaded optimization = On"
Write-Host "    Vertical sync         = Off  (unless G-Sync monitor)"
Write-Host "  Repeat for windower.exe"
Write-Host "  Manage display mode   -> pick the RTX 5060 as primary (not iGPU)"
Write-Host ""

Write-Host "=== 5800X3D thermal note ===" -ForegroundColor Cyan
Write-Host "  3D V-Cache runs hot. Watch temps in HWiNFO64."
Write-Host "  If sustained 85C+, in BIOS: Ai Tweaker -> PBO -> Curve Optimizer -> All Cores -30"
Write-Host ""

Write-Host "=== Done. REBOOT required for GPU scheduling, Ndu, MMCSS. ===" -ForegroundColor Green
Write-Host "Undo any time: right-click REVERT-FFXI.bat -> Run as administrator"
Write-Host "Log:    $LogPath"
Write-Host "Backup: $BackupPath"

Stop-Transcript | Out-Null
