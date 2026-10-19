@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
echo.
echo  ============================================
echo   OpenCode 语音输入 - 一键安装
echo  ============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 (
  echo.
  echo  [失败] 安装未完成。请把上面的内容截图发给分享者。
) else (
  echo.
  echo  [成功] 打开 OpenCode 即可使用:点击输入框右下角麦克风,或按 Ctrl+Alt+Space。
)
echo.
pause
