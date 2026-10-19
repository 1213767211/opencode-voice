#!/bin/bash
# ==oc-voice share== Linux 卸载:恢复原始 app.asar,删除看护任务
set -uo pipefail
STABLE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode-voice"

echo "正在卸载 OpenCode 语音输入..."

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now opencode-voice-repair.timer >/dev/null 2>&1 || true
  rm -f "$HOME/.config/systemd/user/opencode-voice-repair.service" "$HOME/.config/systemd/user/opencode-voice-repair.timer"
fi
if command -v crontab >/dev/null 2>&1; then
  (crontab -l 2>/dev/null | grep -v "opencode-voice-repair") | crontab - 2>/dev/null || true
fi
echo "已删除自动修复任务"

APP=""
[[ -f "$STABLE/appdir.txt" ]] && APP="$(cat "$STABLE/appdir.txt")"
if [[ -n "$APP" && -f "$APP/resources/app.asar.bak-voice" ]]; then
  pkill -f "$APP/" >/dev/null 2>&1 || true
  sleep 2
  ASAR="$APP/resources/app.asar"
  BAK="$ASAR.bak-voice"
  UNPACKED="$APP/resources/app.asar.unpacked"
  UNPACKED_BAK="$UNPACKED.bak-voice"
  rm -f "$ASAR"
  cp "$BAK" "$ASAR" && echo "已恢复原始 app.asar(语音功能已移除)"
  if [[ -d "$UNPACKED_BAK" ]]; then
    rm -rf "$UNPACKED"
    cp -R "$UNPACKED_BAK" "$UNPACKED"
  fi
else
  echo "未找到备份或应用目录,跳过恢复"
fi

read -r -p "是否同时删除语音组件数据目录?(约 300MB) [y/N] " answer
if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
  rm -rf "$STABLE" && echo "已删除数据目录"
fi
echo "卸载完成。"
