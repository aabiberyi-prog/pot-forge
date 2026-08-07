# Keep PotTerminalHelper running. Safe to call repeatedly (e.g. from Task Scheduler).
$ErrorActionPreference = 'Continue'
$helperDir = Split-Path -Parent $PSCommandPath
$script = Join-Path $helperDir 'PotTerminalHelper.ps1'
$vbs = Join-Path $helperDir 'Start-Helper.vbs'
$log = Join-Path $helperDir 'helper.log'

function Write-Log([string]$m) {
    try {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ensure: $m" | Add-Content -LiteralPath $log -Encoding utf8
    } catch {}
}

function Test-HelperRunning {
    $list = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -like '*PotTerminalHelper.ps1*' -and $_.CommandLine -notlike '*Ensure-Helper*'
    }
    return @($list).Count -gt 0
}

if (-not (Test-Path -LiteralPath $script)) {
    Write-Log "missing $script"
    exit 1
}

if (Test-HelperRunning) {
    exit 0
}

Write-Log 'helper not running; starting'
if (Test-Path -LiteralPath $vbs) {
    Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$vbs`"" -WindowStyle Hidden
} else {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $ps -ArgumentList @(
        '-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', $script
    ) -WindowStyle Hidden
}
Start-Sleep -Seconds 2
if (Test-HelperRunning) {
    Write-Log 'started OK'
    exit 0
}
Write-Log 'start FAILED'
exit 2
