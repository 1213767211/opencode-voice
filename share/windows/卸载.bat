@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
if not exist "%~dp0uninstall.ps1" (
  echo.
  echo  [错误] 找不到 uninstall.ps1，请先完整解压压缩包再运行本文件。
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
echo.
pause