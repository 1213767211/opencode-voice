# ==oc-voice== 安装脚本:把语音输入模块打进 OpenCode 的 app.asar
# 用法:
#   powershell -ExecutionPolicy Bypass -File install-voice.ps1 -CloseApp
#   (测试模式) -AppDir <副本路径> -SkipRunningCheck -TestAppId ai.opencode.desktop.voicetest
param(
  [string]$AppDir = "D:\opencode\@opencode-aidesktop",
  [string]$TestAppId = "",
  [switch]$CloseApp,
  [switch]$SkipRunningCheck
)

$ErrorActionPreference = "Stop"
$modDir = $PSScriptRoot
$logFile = Join-Path $modDir "install.log"

function Write-Log([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
  Write-Host $line
  try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch {}
}

trap { Write-Log ("错误: " + $_.Exception.Message); exit 1 }

$resources = Join-Path $AppDir "resources"
$asarPath = Join-Path $resources "app.asar"
$backupPath = "$asarPath.bak-voice"
$unpacked = Join-Path $resources "app.asar.unpacked"
$unpackedBak = "$unpacked.bak-voice"

if (!(Test-Path -LiteralPath (Join-Path $AppDir "OpenCode.exe"))) { throw "未找到 OpenCode.exe,请检查 -AppDir: $AppDir" }
if (!(Test-Path -LiteralPath $asarPath)) {
  if (Test-Path -LiteralPath $backupPath) {
    Write-Log "app.asar 缺失,先从备份恢复"
    Copy-Item -LiteralPath $backupPath -Destination $asarPath
  } else {
    throw "未找到 app.asar: $asarPath"
  }
}

function Stop-OpenCode {
  $procs = Get-Process -Name OpenCode -ErrorAction SilentlyContinue
  if (!$procs) { return }
  if (!$CloseApp) { throw "OpenCode 正在运行,请先退出,或加 -CloseApp 参数自动关闭" }
  Write-Log "关闭 OpenCode..."
  $procs | Stop-Process -Force
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    if (!(Get-Process -Name OpenCode -ErrorAction SilentlyContinue)) { return }
  }
  throw "无法关闭 OpenCode"
}

if (!$SkipRunningCheck) { Stop-OpenCode }

$toolsDir = Join-Path $modDir ".tools"
if (!(Test-Path (Join-Path $toolsDir "node_modules\@electron\asar"))) {
  Write-Log "安装打包工具 @electron/asar..."
  New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
  if (!(Test-Path (Join-Path $toolsDir "package.json"))) {
    Set-Content -LiteralPath (Join-Path $toolsDir "package.json") -Value '{"name":"voice-mod-tools","private":true}' -Encoding Ascii
  }
  & npm install --prefix $toolsDir @electron/asar --no-audit --no-fund --silent
  if ($LASTEXITCODE -ne 0) { throw "npm 安装 @electron/asar 失败" }
}

$work = Join-Path $modDir ".work"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force -Path (Join-Path $work "app") | Out-Null

Write-Log "解包 app.asar(约 150MB)..."
& node (Join-Path $modDir "lib\asar-tool.mjs") extract $asarPath (Join-Path $work "app")
if ($LASTEXITCODE -ne 0) { throw "解包失败" }

$indexPath = Join-Path $work "app\out\main\index.js"
$content = [IO.File]::ReadAllText($indexPath, [Text.Encoding]::UTF8)

if (!(Test-Path $backupPath)) {
  Write-Log "备份原版 app.asar"
  Copy-Item -LiteralPath $asarPath -Destination $backupPath
}

$voiceSrc = Join-Path $modDir "patch\out\voice"
$voiceDst = Join-Path $work "app\out\voice"
New-Item -ItemType Directory -Force -Path $voiceDst | Out-Null
Copy-Item -Path (Join-Path $voiceSrc "*") -Destination $voiceDst -Recurse -Force
Write-Log "已复制语音模块文件"

$appendMarker = "// ==oc-voice-appended=="
$appendIndex = $content.IndexOf($appendMarker)
if ($appendIndex -ge 0) {
  $content = $content.Substring(0, $appendIndex).TrimEnd() + "`r`n"
  Write-Log "检测到已有注入,先移除旧注入"
}
$appendSnippet = [IO.File]::ReadAllText((Join-Path $modDir "patch\append-content.js"), [Text.Encoding]::UTF8)
$content += "`r`n" + $appendSnippet.TrimEnd() + "`r`n"
Write-Log "已注入语音模块入口"

$updaterOriginal = 'const UPDATER_ENABLED = app.isPackaged && CHANNEL !== "dev";'
if ($content.Contains($updaterOriginal)) {
  $content = $content.Replace($updaterOriginal, 'const UPDATER_ENABLED = false; // ==oc-voice: auto update disabled to keep patch')
  Write-Log "已关闭自动更新(防止覆盖补丁)"
}

if ($TestAppId) {
  $content = $content.Replace('prod: "ai.opencode.desktop"', ('prod: "' + $TestAppId + '"'))
  Write-Log "测试模式:应用独立 AppId $TestAppId"
}

[IO.File]::WriteAllText($indexPath, $content, (New-Object Text.UTF8Encoding($false)))

Write-Log "重新打包 app.asar..."
$newAsar = Join-Path $work "app.asar.new"
& node (Join-Path $modDir "lib\asar-tool.mjs") pack (Join-Path $work "app") $newAsar "node_modules/**"
if ($LASTEXITCODE -ne 0) { throw "打包失败" }
if (!(Test-Path -LiteralPath $newAsar)) { throw "打包输出不存在" }
if (!(Test-Path -LiteralPath "$newAsar.unpacked")) { throw "未生成 unpacked 目录" }

if (!$SkipRunningCheck) { Stop-OpenCode }

function Invoke-WithRetry {
  param([scriptblock]$Action, [string]$Label, [int]$Attempts = 10)
  for ($i = 1; $i -le $Attempts; $i++) {
    try { & $Action; return } catch {
      if ($i -eq $Attempts) { throw ("{0} 失败: {1}" -f $Label, $_.Exception.Message) }
      Write-Log ("{0} 第 {1} 次失败,重试: {2}" -f $Label, $i, $_.Exception.Message)
      Start-Sleep -Milliseconds (400 * $i)
    }
  }
}

$oldUnpacked = "$unpacked.old-voice"
if (!(Test-Path -LiteralPath $unpackedBak) -and (Test-Path -LiteralPath $unpacked)) {
  Invoke-WithRetry { Rename-Item -LiteralPath $unpacked -NewName (Split-Path $unpackedBak -Leaf) } "备份原版 unpacked"
} elseif (Test-Path -LiteralPath $unpacked) {
  if (Test-Path -LiteralPath $oldUnpacked) {
    Invoke-WithRetry { Remove-Item -Recurse -Force -LiteralPath $oldUnpacked } "清理遗留目录"
  }
  Invoke-WithRetry { Rename-Item -LiteralPath $unpacked -NewName (Split-Path $oldUnpacked -Leaf) } "移开旧 unpacked"
}
Invoke-WithRetry { Remove-Item -LiteralPath $asarPath -Force } "删除旧 app.asar"
Invoke-WithRetry { Move-Item -LiteralPath $newAsar -Destination $asarPath } "写入新 app.asar"
Invoke-WithRetry { Move-Item -LiteralPath "$newAsar.unpacked" -Destination $unpacked } "写入新 unpacked"
if (Test-Path -LiteralPath $oldUnpacked) {
  try { Remove-Item -Recurse -Force -LiteralPath $oldUnpacked } catch { Write-Log "提示: 残留旧目录可稍后手动删除: $oldUnpacked" }
}

$voiceCount = 0
& node (Join-Path $modDir "lib\asar-tool.mjs") list $asarPath | ForEach-Object { if ($_ -match "voice") { $voiceCount++ } }
if ($voiceCount -eq 0) { throw "验证失败:打包后的 asar 中未找到语音模块" }

$nativeCount = (Get-ChildItem -LiteralPath $unpacked -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in ".node", ".exe" } | Measure-Object).Count
if ($nativeCount -eq 0) { Write-Log "警告: 新的 app.asar.unpacked 中没有原生模块文件" } else { Write-Log ("原生模块文件: {0} 个" -f $nativeCount) }

$size = (Get-Item -LiteralPath $asarPath).Length / 1MB
Write-Log ("安装完成! app.asar {0:N1} MB,内含语音模块文件 {1} 个" -f $size, $voiceCount)
Write-Log "启动 OpenCode 后按快捷键说话即可(默认 Ctrl+Alt+Space)"
