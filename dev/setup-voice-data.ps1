# ==oc-voice== 下载语音引擎与模型(离线识别,只需运行一次)
# 用法: powershell -ExecutionPolicy Bypass -File setup-voice-data.ps1
param(
  [string]$DataDir = "D:\opencode\voice-data"
)

$ErrorActionPreference = "Stop"
$modDir = $PSScriptRoot

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DataDir "logs") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DataDir "tmp") | Out-Null

Write-Host "开始下载/校验语音引擎与模型(引擎约 25MB,模型约 240MB)..."
& node (Join-Path $modDir "lib\fetch-assets.mjs") $DataDir
if ($LASTEXITCODE -ne 0) { throw "下载失败,请检查网络后重试" }

$configPath = Join-Path $DataDir "config.json"
if (!(Test-Path $configPath)) {
  $default = @'
{
  "hotkey": "Control+Alt+Space",
  "language": "auto",
  "threads": 0,
  "maxSeconds": 120
}
'@
  [IO.File]::WriteAllText($configPath, $default, (New-Object Text.UTF8Encoding($false)))
  Write-Host "已生成默认配置: $configPath"
}

Write-Host ""
Write-Host "语音数据已就绪: $DataDir"
Write-Host "如需修改快捷键,编辑 $configPath 中的 hotkey 字段,然后重启 OpenCode。"
