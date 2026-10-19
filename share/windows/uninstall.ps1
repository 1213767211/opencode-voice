# ==oc-voice share== 卸载:恢复原始 app.asar,删除自动修复任务
param(
  [string]$StableDir = ""
)
$ErrorActionPreference = "Stop"
if (!$StableDir) { $StableDir = Join-Path $env:LOCALAPPDATA "OpenCodeVoice" }

Write-Host "正在卸载 OpenCode 语音输入..."

try { & schtasks.exe /Delete /F /TN "OpenCodeVoiceRepair" | Out-Null } catch {}
Write-Host "已删除自动修复任务"

$appDir = $null
$savedFile = Join-Path $StableDir "appdir.txt"
if (Test-Path -LiteralPath $savedFile) {
  $appDir = (Get-Content -LiteralPath $savedFile -Raw).Trim()
}
if ($appDir -and (Test-Path -LiteralPath (Join-Path $appDir "resources\app.asar.bak-voice"))) {
  try {
    Get-Process -Name OpenCode -ErrorAction SilentlyContinue | Where-Object {
      $_.Path -and $_.Path.ToLower().StartsWith($appDir.ToLower())
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $asar = Join-Path $appDir "resources\app.asar"
    $bak = "$asar.bak-voice"
    $unpacked = Join-Path $appDir "resources\app.asar.unpacked"
    $unpackedBak = "$unpacked.bak-voice"
    Remove-Item -LiteralPath $asar -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $bak -Destination $asar -Force
    if (Test-Path -LiteralPath $unpackedBak) {
      if (Test-Path -LiteralPath $unpacked) { Remove-Item -Recurse -Force -LiteralPath $unpacked }
      Copy-Item -LiteralPath $unpackedBak -Destination $unpacked -Recurse -Force
    }
    Write-Host "已恢复原始 app.asar(语音功能已移除)"
  } catch {
    Write-Host "恢复 app.asar 失败: $($_.Exception.Message)"
    Write-Host "请手动把 resources\app.asar.bak-voice 复制回 app.asar"
  }
} else {
  Write-Host "未找到备份或 OpenCode 目录,跳过恢复(可能已卸载)"
}

$answer = Read-Host "是否同时删除语音组件数据目录 $StableDir ?(约 300MB) [y/N]"
if ($answer -match "^(?i)y") {
  try { Remove-Item -Recurse -Force -LiteralPath $StableDir } catch { Write-Host "删除失败(可能被占用): $StableDir" }
  Write-Host "已删除数据目录"
}
Write-Host "卸载完成。"
