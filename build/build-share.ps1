# ==oc-voice share== 组装三个平台安装包并打 zip
$ErrorActionPreference = "Stop"
$dist = "D:\opencode\voice-mod\dist"
$outRoot = Join-Path $dist "share"
$zipRoot = Join-Path $dist "zips"
$patch = "D:\opencode\voice-mod\patch"
$model = "D:\opencode\voice-data\model"
$toolsSrc = "D:\opencode\voice-mod\share-tools"

function Reset-Dir([string]$Path) {
  if (Test-Path -LiteralPath $Path) { Remove-Item -Recurse -Force -LiteralPath $Path }
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Copy-Tools([string]$Dst) {
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null
  foreach ($f in @("patch-app.mjs", "check-patched.mjs", "package.json")) {
    Copy-Item -LiteralPath (Join-Path $toolsSrc $f) -Destination $Dst -Force
  }
  Copy-Item -LiteralPath (Join-Path $toolsSrc "node_modules") -Destination (Join-Path $Dst "node_modules") -Recurse -Force
}

function Copy-PatchAndModel([string]$Root) {
  $p = Join-Path $Root "patch"
  New-Item -ItemType Directory -Force -Path (Join-Path $p "out") | Out-Null
  Copy-Item -LiteralPath (Join-Path $patch "out\voice") -Destination (Join-Path $p "out\voice") -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $patch "append-content.js") -Destination (Join-Path $p "append-content.js") -Force
  $m = Join-Path $Root "model"
  New-Item -ItemType Directory -Force -Path $m | Out-Null
  Copy-Item -LiteralPath (Join-Path $model "model.int8.onnx") -Destination $m -Force
  Copy-Item -LiteralPath (Join-Path $model "tokens.txt") -Destination $m -Force
}

New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
New-Item -ItemType Directory -Force -Path $zipRoot | Out-Null

# ---------- Windows ----------
$win = Join-Path $outRoot "oc-voice-windows-x64"
Reset-Dir $win
Copy-PatchAndModel $win
Copy-Item -LiteralPath "D:\opencode\voice-data\engine\sherpa-onnx-v1.13.8-win-x64-shared-MT-Release" -Destination (Join-Path $win "engine") -Recurse -Force
Copy-Tools (Join-Path $win "tools")
Copy-Item -LiteralPath (Join-Path $toolsSrc "repair.ps1") -Destination (Join-Path $win "tools\repair.ps1") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "install.ps1") -Destination (Join-Path $win "install.ps1") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "uninstall.ps1") -Destination (Join-Path $win "uninstall.ps1") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "安装.bat") -Destination (Join-Path $win "安装.bat") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "卸载.bat") -Destination (Join-Path $win "卸载.bat") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "readme-windows.txt") -Destination (Join-Path $win "README.txt") -Force
Write-Host "windows staged"

# ---------- macOS ----------
$mac = Join-Path $outRoot "oc-voice-macos-universal"
Reset-Dir $mac
Copy-PatchAndModel $mac
Copy-Item -LiteralPath (Join-Path $dist "engines\sherpa-onnx-v1.13.8-osx-universal2-shared") -Destination (Join-Path $mac "engine") -Recurse -Force
Copy-Tools (Join-Path $mac "tools")
Copy-Item -LiteralPath (Join-Path $toolsSrc "mac\repair.sh") -Destination (Join-Path $mac "tools\repair.sh") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "mac\install-mac.sh") -Destination (Join-Path $mac "install-mac.sh") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "mac\uninstall-mac.sh") -Destination (Join-Path $mac "uninstall-mac.sh") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "mac\安装.command") -Destination (Join-Path $mac "安装.command") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "mac\卸载.command") -Destination (Join-Path $mac "卸载.command") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "readme-macos.txt") -Destination (Join-Path $mac "README.txt") -Force
Write-Host "macos staged"

# ---------- Linux ----------
$lin = Join-Path $outRoot "oc-voice-linux-x64"
Reset-Dir $lin
Copy-PatchAndModel $lin
Copy-Item -LiteralPath (Join-Path $dist "engines\sherpa-onnx-v1.13.8-linux-x64-shared") -Destination (Join-Path $lin "engine") -Recurse -Force
Copy-Tools (Join-Path $lin "tools")
Copy-Item -LiteralPath (Join-Path $toolsSrc "linux\repair.sh") -Destination (Join-Path $lin "tools\repair.sh") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "linux\install-linux.sh") -Destination (Join-Path $lin "install-linux.sh") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "linux\uninstall-linux.sh") -Destination (Join-Path $lin "uninstall-linux.sh") -Force
Copy-Item -LiteralPath (Join-Path $toolsSrc "readme-linux.txt") -Destination (Join-Path $lin "README.txt") -Force
Write-Host "linux staged"

# ---------- ZIP ----------
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($name in @("oc-voice-windows-x64", "oc-voice-macos-universal", "oc-voice-linux-x64")) {
  $srcDir = Join-Path $outRoot $name
  $zip = Join-Path $zipRoot "$name.zip"
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
  [System.IO.Compression.ZipFile]::CreateFromDirectory(
    $srcDir, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true, [System.Text.Encoding]::UTF8
  )
  $size = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)
  Write-Host "zip: $zip ($size MB)"
}
Write-Host "DONE"
