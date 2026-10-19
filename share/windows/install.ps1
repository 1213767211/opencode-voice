# ==oc-voice share== Windows 一键安装器
# 自动探测 OpenCode 安装目录,把语音输入模块打入 app.asar,并安装“更新修复”计划任务。
# 用法: install.ps1 [-AppDir <dir>] [-StableDir <dir>] [-Repair] [-NoWatcher] [-Quiet]
param(
  [string]$AppDir = "",
  [string]$StableDir = "",
  [switch]$Repair,
  [switch]$NoWatcher,
  [switch]$Quiet,
  [string]$AppId = ""
)

$ErrorActionPreference = "Stop"

$scriptName = "oc-voice-windows"
if (!$StableDir) { $StableDir = Join-Path $env:LOCALAPPDATA "OpenCodeVoice" }
$logFile = Join-Path $StableDir "install.log"

function Write-Log([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
  if (!$Quiet) { Write-Host $line }
  try {
    New-Item -ItemType Directory -Force -Path $StableDir | Out-Null
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
  } catch {}
}

function Fail([string]$Message) {
  Write-Log ("错误: " + $Message)
  if ($Quiet) { exit 1 }
  Write-Host ""
  Write-Host "安装失败:" $Message -ForegroundColor Red
  exit 1
}

trap { Fail $_.Exception.Message }

function Test-Admin {
  try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

function Get-NodeExe([string]$Dir) {
  $candidates = @()
  foreach ($name in @("OpenCode.exe", "opencode.exe", "OpenCode Desktop.exe")) {
    $candidates += (Join-Path $Dir $name)
  }
  try {
    $candidates += (Get-ChildItem -LiteralPath $Dir -Filter "*.exe" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "(?i)opencode" } | ForEach-Object { $_.FullName })
  } catch {}
  foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
  return $null
}

function Test-AppDir([string]$Dir) {
  if (!$Dir -or !(Test-Path -LiteralPath $Dir)) { return $false }
  if (!(Test-Path -LiteralPath (Join-Path $Dir "resources\app.asar"))) { return $false }
  return [bool](Get-NodeExe $Dir)
}

function Find-AppDir {
  $candidates = @()
  $savedFile = Join-Path $StableDir "appdir.txt"
  if (Test-Path -LiteralPath $savedFile) {
    $saved = (Get-Content -LiteralPath $savedFile -Raw -ErrorAction SilentlyContinue)
    if ($saved) { $candidates += $saved.Trim() }
  }
  try {
    $procs = Get-Process -Name OpenCode -ErrorAction SilentlyContinue
    foreach ($p in $procs) { if ($p.Path) { $candidates += (Split-Path $p.Path -Parent) } }
  } catch {}
  try {
    $roots = @(
      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
      "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
      "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($root in $roots) {
      if (!(Test-Path $root)) { continue }
      Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
        try {
          $item = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
          if ($item -and $item.DisplayName -match "(?i)opencode" -and $item.InstallLocation) {
            $script:candidates += $item.InstallLocation
          }
        } catch {}
      }
    }
  } catch {}
  $common = @()
  if ($env:LOCALAPPDATA) {
    $common += (Join-Path $env:LOCALAPPDATA "Programs\OpenCode")
    $common += (Join-Path $env:LOCALAPPDATA "Programs\opencode")
    $common += (Join-Path $env:LOCALAPPDATA "Programs\opencode-desktop")
    $common += (Join-Path $env:LOCALAPPDATA "OpenCode")
    $common += (Join-Path $env:LOCALAPPDATA "opencode-desktop")
  }
  if ($env:ProgramFiles) { $common += (Join-Path $env:ProgramFiles "OpenCode") }
  if (${env:ProgramFiles(x86)}) { $common += (Join-Path ${env:ProgramFiles(x86)} "OpenCode") }
  $candidates += $common
  foreach ($c in $candidates) {
    if (Test-AppDir $c) { return (Resolve-Path -LiteralPath $c).Path }
  }
  return $null
}

function Close-App([string]$Dir) {
  $targets = @()
  try {
    $targets = Get-Process -Name OpenCode -ErrorAction SilentlyContinue | Where-Object {
      $_.Path -and $_.Path.ToLower().StartsWith($Dir.ToLower())
    }
  } catch {}
  if (!$targets) { return $true }
  Write-Log "正在关闭 OpenCode..."
  $targets | Stop-Process -Force -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500
    try {
      $left = Get-Process -Name OpenCode -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.ToLower().StartsWith($Dir.ToLower())
      }
      if (!$left) { return $true }
    } catch { return $true }
  }
  return $false
}

function Invoke-NodeTool([string]$NodeExe, [string[]]$ToolArgs) {
  $prev = $env:ELECTRON_RUN_AS_NODE
  $prevNoAsar = $env:ELECTRON_NO_ASAR
  $env:ELECTRON_RUN_AS_NODE = "1"
  $env:ELECTRON_NO_ASAR = "1"
  try {
    if ($Quiet) {
      & $NodeExe @ToolArgs 2>&1 | Out-Null
    } else {
      & $NodeExe @ToolArgs 2>&1 | Out-Host
    }
    return $LASTEXITCODE
  } finally {
    if ($null -eq $prev) { Remove-Item Env:\ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue }
    else { $env:ELECTRON_RUN_AS_NODE = $prev }
    if ($null -eq $prevNoAsar) { Remove-Item Env:\ELECTRON_NO_ASAR -ErrorAction SilentlyContinue }
    else { $env:ELECTRON_NO_ASAR = $prevNoAsar }
  }
}

# ---------- 主流程 ----------

Write-Log ("== oc-voice 安装开始 (repair=$($Repair.IsPresent)) ==")

if (!$AppDir) {
  Write-Log "正在自动探测 OpenCode 安装目录..."
  $AppDir = Find-AppDir
  if (!$AppDir) {
    if ($Repair) { Write-Log "未找到 OpenCode 安装目录,稍后重试"; exit 0 }
    Write-Host ""
    Write-Host "没有自动找到 OpenCode 的安装位置。" -ForegroundColor Yellow
    Write-Host "请把 OpenCode 的安装文件夹(里面应有 OpenCode.exe 和 resources 文件夹)直接拖到本窗口,然后按回车:"
    $input = Read-Host
    $input = $input.Trim('"').Trim()
    if (Test-AppDir $input) { $AppDir = $input } else { Fail "目录无效: $input" }
  }
}
$AppDir = (Resolve-Path -LiteralPath $AppDir).Path
if (!(Test-AppDir $AppDir)) { Fail "不是有效的 OpenCode 目录: $AppDir" }
Write-Log "OpenCode 目录: $AppDir"

$resources = Join-Path $AppDir "resources"
$asarPath = Join-Path $resources "app.asar"

# 权限检查(Program Files 需要管理员)
$needsAdmin = $false
try {
  $probe = Join-Path $resources (".ocv-write-test-" + [guid]::NewGuid().ToString("N"))
  [IO.File]::WriteAllText($probe, "x")
  Remove-Item -LiteralPath $probe -Force
} catch { $needsAdmin = $true }
if ($needsAdmin -and !(Test-Admin)) {
  if ($Repair) { Write-Log "需要管理员权限,跳过本次"; exit 0 }
  Write-Log "需要管理员权限,正在提权..."
  $argList = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"",
    "-AppDir", "`"$AppDir`"", "-StableDir", "`"$StableDir`""
  )
  Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList -Wait
  exit $LASTEXITCODE
}

# 关闭应用
if (!(Close-App $AppDir)) {
  if ($Repair) { Write-Log "OpenCode 未能关闭,稍后重试"; exit 0 }
  Fail "无法关闭 OpenCode,请手动退出后重试"
}

# 资产来源:正式安装用安装包内 assets;修复时用 StableDir 里已存的副本
$sourceRoot = $StableDir
if (!$Repair) {
  $packageRoot = $PSScriptRoot
  if (!(Test-Path -LiteralPath (Join-Path $packageRoot "patch\out\voice\main.js"))) {
    $up = Split-Path $packageRoot -Parent
    if (Test-Path -LiteralPath (Join-Path $up "patch\out\voice\main.js")) { $packageRoot = $up }
  }
  if (!(Test-Path -LiteralPath (Join-Path $packageRoot "patch\out\voice\main.js"))) {
    Fail "安装包文件不完整(缺少 patch),请重新解压安装包"
  }
  $sameDir = $false
  try { $sameDir = ((Resolve-Path -LiteralPath $packageRoot).Path -eq (Resolve-Path -LiteralPath $StableDir).Path) } catch {}
  if (!$sameDir) {
    Write-Log "正在复制语音组件到 $StableDir (约 300MB,请稍候)..."
    New-Item -ItemType Directory -Force -Path $StableDir | Out-Null
    foreach ($part in @("patch", "engine", "model")) {
      $src = Join-Path $packageRoot $part
      if (Test-Path -LiteralPath $src) {
        $dst = Join-Path $StableDir $part
        if (Test-Path -LiteralPath $dst) { Remove-Item -Recurse -Force -LiteralPath $dst }
        Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
      }
    }
    $toolsSrc = Join-Path $packageRoot "tools"
    $toolsDst = Join-Path $StableDir "tools"
    New-Item -ItemType Directory -Force -Path $toolsDst | Out-Null
    Copy-Item -Path (Join-Path $toolsSrc "*") -Destination $toolsDst -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $packageRoot "install.ps1") -Destination (Join-Path $toolsDst "install.ps1") -Force -ErrorAction SilentlyContinue
    $configFile = Join-Path $StableDir "config.json"
    if (!(Test-Path -LiteralPath $configFile)) {
      Set-Content -LiteralPath $configFile -Value '{"hotkey":"Control+Alt+Space","language":"auto","threads":0,"maxSeconds":120}' -Encoding Ascii
    }
    Write-Log "语音组件已就位"
  }
}

if (!(Test-Path -LiteralPath (Join-Path $sourceRoot "patch\out\voice\main.js"))) {
  if ($Repair) { Write-Log "组件缺失,跳过"; exit 0 }
  Fail "组件缺失: $sourceRoot\patch"
}

$nodeExe = Get-NodeExe $AppDir

# 已打过补丁且在修复模式下 => 直接结束
if ($Repair) {
  $checkCode = Invoke-NodeTool $nodeExe @((Join-Path $sourceRoot "tools\check-patched.mjs"), $asarPath)
  if ($checkCode -eq 0) { exit 0 }
  Write-Log "检测到补丁缺失(可能刚更新),正在自动修复..."
}

# 打补丁
$patchArgs = @(
  (Join-Path $sourceRoot "tools\patch-app.mjs"),
  "--app-asar", $asarPath,
  "--patch", (Join-Path $sourceRoot "patch")
)
if ($Repair) { $patchArgs += "--refresh-backup" }
if ($AppId) { $patchArgs += @("--app-id", $AppId) }
if ($Quiet) { $patchArgs += "--quiet" }
$code = Invoke-NodeTool $nodeExe $patchArgs
if ($code -ne 0) { Fail "补丁应用失败(exit $code),请把 $logFile 发给分享者" }

$checkCode = Invoke-NodeTool $nodeExe @((Join-Path $sourceRoot "tools\check-patched.mjs"), $asarPath)
if ($checkCode -ne 0) { Fail "校验失败:补丁未生效" }

# 记录目录,供修复任务使用
Set-Content -LiteralPath (Join-Path $StableDir "appdir.txt") -Value $AppDir -Encoding UTF8

# 安装修复看护(计划任务)
if (!$NoWatcher) {
  try {
    $repairScript = Join-Path $StableDir "tools\repair.ps1"
    $taskName = "OpenCodeVoiceRepair"
    $action = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$repairScript`""
    $extra = @()
    if (Test-Admin) { $extra = @("/RL", "HIGHEST") }
    & schtasks.exe /Create /F /TN $taskName /SC MINUTE /MO 10 /TR $action @extra | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Log "已安装自动修复任务(每10分钟检查一次,更新后自动还原语音功能)" }
    else { Write-Log "提示: 自动修复任务创建失败(exit $LASTEXITCODE),更新后如语音消失请重新运行安装包" }
  } catch { Write-Log ("提示: 自动修复任务创建异常: " + $_.Exception.Message) }
}

Write-Log "安装完成! 打开 OpenCode 后按 Ctrl+Alt+Space 或点输入框右下角麦克风开始说话。"
if (!$Quiet) {
  Write-Host ""
  Write-Host "安装完成!" -ForegroundColor Green
  Write-Host "打开 OpenCode,点击输入框右下角的麦克风,或按快捷键 Ctrl+Alt+Space 即可语音输入。"
}
exit 0
