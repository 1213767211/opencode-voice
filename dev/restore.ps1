# ==oc-voice== 还原脚本:恢复安装补丁前的原始 app.asar
# 用法: powershell -ExecutionPolicy Bypass -File restore.ps1 -CloseApp
param(
  [string]$AppDir = "D:\opencode\@opencode-aidesktop",
  [switch]$CloseApp,
  [switch]$SkipRunningCheck
)

$ErrorActionPreference = "Stop"

$resources = Join-Path $AppDir "resources"
$asarPath = Join-Path $resources "app.asar"
$backupPath = "$asarPath.bak-voice"
$unpacked = Join-Path $resources "app.asar.unpacked"
$unpackedBak = "$unpacked.bak-voice"

if (!(Test-Path -LiteralPath $backupPath)) { throw "未找到备份: $backupPath,无法还原" }

function Stop-OpenCode {
  $procs = Get-Process -Name OpenCode -ErrorAction SilentlyContinue
  if (!$procs) { return }
  if (!$CloseApp) { throw "OpenCode 正在运行,请先退出,或加 -CloseApp 参数自动关闭" }
  $procs | Stop-Process -Force
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    if (!(Get-Process -Name OpenCode -ErrorAction SilentlyContinue)) { return }
  }
  throw "无法关闭 OpenCode"
}

if (!$SkipRunningCheck) { Stop-OpenCode }

if (Test-Path -LiteralPath $unpacked) { Remove-Item -Recurse -Force -LiteralPath $unpacked }
if (Test-Path -LiteralPath $unpackedBak) { Rename-Item -LiteralPath $unpackedBak -NewName (Split-Path $unpacked -Leaf) }
Remove-Item -LiteralPath $asarPath -Force
Copy-Item -LiteralPath $backupPath -Destination $asarPath

Write-Host "已还原为原版 app.asar"
