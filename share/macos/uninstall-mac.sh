#!/bin/bash
# ==oc-voice share== macOS 卸载:恢复原始 app.asar,删除看护任务
set -uo pipefail
STABLE="$HOME/Library/Application Support/OpenCodeVoice"

echo "正在卸载 OpenCode 语音输入..."

PLIST="$HOME/Library/LaunchAgents/ai.opencode.voice.repair.plist"
launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
echo "已删除自动修复任务"

APP=""
[[ -f "$STABLE/appdir.txt" ]] && APP="$(cat "$STABLE/appdir.txt")"
if [[ -n "$APP" && -f "$APP/Contents/Resources/app.asar.bak-voice" ]]; then
  pkill -f "$APP/Contents/MacOS" >/dev/null 2>&1 || true
  sleep 2
  ASAR="$APP/Contents/Resources/app.asar"
  BAK="$ASAR.bak-voice"
  UNPACKED="$APP/Contents/Resources/app.asar.unpacked"
  UNPACKED_BAK="$UNPACKED.bak-voice"
  rm -f "$ASAR"
  cp "$BAK" "$ASAR" && echo "已恢复原始 app.asar(语音功能已移除)"
  if [[ -d "$UNPACKED_BAK" ]]; then
    rm -rf "$UNPACKED"
    cp -R "$UNPACKED_BAK" "$UNPACKED"
  fi
  codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
else
  echo "未找到备份或应用目录,跳过恢复"
fi

read -r -p "是否同时删除语音组件数据目录?(约 300MB) [y/N] " answer
if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
  rm -rf "$STABLE" && echo "已删除数据目录"
fi
echo "卸载完成。"
read -n 1 -s -r -p "按任意键退出..."
