# ==oc-voice share== 卸载:恢复原始 app.asar,删除自动修复任务与语音组件
param(
  [string]$StableDir = "",
  [string]$AppDir = ""
)
$ErrorActionPreference = "Stop"

function Test-AsciiPath([string]$p) { return ($p -notmatch '[^\x20-\x7E]') }
$defaultDataDir = Join-Path $env:LOCALAPPDATA "OpenCodeVoice"

function Get-AppDirs {
  $dirs = @()
  if ($AppDir) { $dirs += $AppDir }
  try {
    $dirs += (Get-Process -Name OpenCode -ErrorAction SilentlyContinue | Where-Object { $_.Path } | ForEach-Object { Split-Path $_.Path -Parent })
  } catch {}
  try {
    foreach ($root in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
      if (!(Test-Path $root)) { continue }
      Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
        $item = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($item -and $item.DisplayName -match "(?i)opencode" -and $item.InstallLocation) { $dirs += $item.InstallLocation }
      }
    }
  } catch {}
  return ($dirs | Select-Object -Unique)
}

Write-Host "正在卸载 OpenCode 语音输入..."

# 1) 数据目录:引导配置 -> 常见位置 -> OpenCode 文件夹下的 voice-data
if (!$StableDir) {
  $bootstrapCfg = Join-Path $defaultDataDir "config.json"
  if (Test-Path -LiteralPath $bootstrapCfg) {
    try {
      $j = Get-Content -LiteralPath $bootstrapCfg -Raw | ConvertFrom-Json
      if ($j.dataDir -and (Test-Path -LiteralPath (Join-Path $j.dataDir "patch"))) { $StableDir = $j.dataDir }
    } catch {}
  }
}
if (!$StableDir) {
  foreach ($c in @((Join-Path $env:LOCALAPPDATA "OpenCodeVoice"), (Join-Path $env:ProgramData "OpenCodeVoice"))) {
    if (Test-Path -LiteralPath (Join-Path $c "patch")) { $StableDir = $c; break }
  }
}
$appDirs = @(Get-AppDirs)
if (!$StableDir) {
  foreach ($d in $appDirs) {
    foreach ($c in @((Join-Path $d "voice-data"), (Join-Path (Split-Path $d -Parent) "voice-data"))) {
      if (Test-Path -LiteralPath (Join-Path $c "patch")) { $StableDir = $c; break }
    }
    if ($StableDir) { break }
  }
}

# 2) OpenCode 目录
if (!$AppDir -and $StableDir) {
  $savedFile = Join-Path $StableDir "appdir.txt"
  if (Test-Path -LiteralPath $savedFile) {
    $saved = (Get-Content -LiteralPath $savedFile -Raw -ErrorAction SilentlyContinue)
    if ($saved) { $AppDir = $saved.Trim() }
  }
}
if (!$AppDir) {
  foreach ($d in $appDirs) {
    if (Test-Path -LiteralPath (Join-Path $d "resources\app.asar.bak-voice")) { $AppDir = $d; break }
  }
}
if (!$AppDir) {
  Write-Host ""
  Write-Host "没有自动找到 OpenCode 安装目录。" -ForegroundColor Yellow
  Write-Host "请把 OpenCode 的安装文件夹(里面有 OpenCode.exe 和 resources)拖到本窗口,然后按回车(留空则跳过):"
  $drag = Read-Host
  $drag = $drag.Trim('"').Trim()
  if ($drag -and (Test-Path -LiteralPath (Join-Path $drag "resources\app.asar"))) {
    $AppDir = $drag
    if (!$StableDir -and (Test-Path -LiteralPath (Join-Path $AppDir "voice-data\patch"))) { $StableDir = Join-Path $AppDir "voice-data" }
  }
}
if (!$StableDir) { $StableDir = $defaultDataDir }

# 3) 恢复原始 app.asar
if ($AppDir) {
  $bak = Join-Path $AppDir "resources\app.asar.bak-voice"
  if (Test-Path -LiteralPath $bak) {
    try {
      Get-Process -Name OpenCode -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.ToLower().StartsWith($AppDir.ToLower())
      } | Stop-Process -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
      $asar = Join-Path $AppDir "resources\app.asar"
      $unpacked = Join-Path $AppDir "resources\app.asar.unpacked"
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
    Write-Host "未找到 app.asar 备份,跳过恢复(可能已卸载或从未安装)"
  }
} else {
  Write-Host "跳过恢复 app.asar(未定位到 OpenCode 目录)"
}

# 4) 删除更新监视与旧的自动修复任务
try { & schtasks.exe /Delete /F /TN "OpenCodeVoiceRepair" 2>$null | Out-Null } catch {}
try {
  $startup = [Environment]::GetFolderPath("Startup")
  $vbsPath = Join-Path $startup "OpenCodeVoiceWatch.vbs"
  if (Test-Path -LiteralPath $vbsPath) { Remove-Item -LiteralPath $vbsPath -Force -ErrorAction SilentlyContinue }
  $watchScript = Join-Path $StableDir "tools\watch.ps1"
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($watchScript) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch {}
Write-Host "已删除更新监视"

# 5) 删除数据目录
if ($StableDir -and (Test-Path -LiteralPath $StableDir)) {
  $answer = Read-Host "是否同时删除语音组件数据目录 $StableDir ?(约 300MB) [y/N]"
  if ($answer -match "^(?i)y") {
    try { Remove-Item -Recurse -Force -LiteralPath $StableDir } catch { Write-Host "删除失败(可能被占用): $StableDir" }
    if (!(Test-Path -LiteralPath $StableDir)) { Write-Host "已删除数据目录" }
  }
}

# 6) 清理默认位置的残留配置与空目录
foreach ($c in @($defaultDataDir, (Join-Path $env:ProgramData "OpenCodeVoice"))) {
  if (!$c -or !(Test-Path -LiteralPath $c)) { continue }
  $same = $false
  try { $same = ($c.TrimEnd([char]"\") -ieq $StableDir.TrimEnd([char]"\") ) } catch {}
  if ($same) { continue }
  $cfgFile = Join-Path $c "config.json"
  if (Test-Path -LiteralPath $cfgFile) {
    try {
      $j = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
      if ($j.dataDir) { Remove-Item -LiteralPath $cfgFile -Force -ErrorAction SilentlyContinue }
    } catch {}
  }
  $left = Get-ChildItem -LiteralPath $c -Force -ErrorAction SilentlyContinue
  if (!$left) { Remove-Item -LiteralPath $c -Force -ErrorAction SilentlyContinue }
}
Write-Host "卸载完成。"