# ==oc-voice share== 自动修复脚本(由计划任务每10分钟调用一次)
# 若 OpenCode 更新后 app.asar 里的语音补丁丢失,会自动重新打上。
$ErrorActionPreference = "Continue"
$stable = $env:OCV_STABLE
if (!$stable) { $stable = Join-Path $env:LOCALAPPDATA "OpenCodeVoice" }
try {
  & (Join-Path $PSScriptRoot "install.ps1") -Repair -Quiet -StableDir $stable
} catch {}
exit 0
