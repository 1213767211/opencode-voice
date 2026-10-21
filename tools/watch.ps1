# ==oc-voice share== 更新监视:仅在 OpenCode 更新(app.asar 变化)后触发修复,平时不运行
$ErrorActionPreference = "Continue"
$stable = Split-Path $PSScriptRoot -Parent
$repair = Join-Path $PSScriptRoot "repair.ps1"
$appDirFile = Join-Path $stable "appdir.txt"
function Get-AppDir { if (Test-Path -LiteralPath $appDirFile) { return (Get-Content -LiteralPath $appDirFile -Raw).Trim() } return $null }
$appDir = Get-AppDir
if (!$appDir) { exit 0 }
$res = Join-Path $appDir "resources"
if (!(Test-Path -LiteralPath $res)) { exit 0 }
& $repair
try {
  $watcher = New-Object IO.FileSystemWatcher $res, "app.asar"
  $watcher.NotifyFilter = [IO.NotifyFilters]::FileName -bor [IO.NotifyFilters]::LastWrite -bor [IO.NotifyFilters]::Size
  $watcher.EnableRaisingEvents = $true
  while ($true) {
    $change = $watcher.WaitForChanged([IO.WatcherChangeTypes]::All, 60000)
    if ($change.TimedOut) { continue }
    Start-Sleep -Seconds 5
    for ($i = 0; $i -lt 20; $i++) {
      & $repair
      Start-Sleep -Seconds 30
    }
  }
} catch { exit 0 }