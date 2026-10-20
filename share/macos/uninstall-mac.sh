#!/bin/bash
# ==oc-voice share== macOS 卸载:恢复原始 app.asar,删除看护任务与语音组件
set -uo pipefail

DEFAULT_STABLE="$HOME/Library/Application Support/OpenCodeVoice"
STABLE="${OCV_STABLE:-}"

echo "正在卸载 OpenCode 语音输入..."

find_app() {
  local cands=()
  if [[ -n "$STABLE" && -f "$STABLE/appdir.txt" ]]; then
    cands+=("$(cat "$STABLE/appdir.txt")")
  fi
  if [[ -f "$DEFAULT_STABLE/appdir.txt" ]]; then
    cands+=("$(cat "$DEFAULT_STABLE/appdir.txt")")
  fi
  cands+=("/Applications/OpenCode.app" "$HOME/Applications/OpenCode.app")
  if command -v pgrep >/dev/null 2>&1; then
    local p cmd
    for p in $(pgrep -f "OpenCode.app/Contents/MacOS" 2>/dev/null); do
      cmd="$(ps -p "$p" -o command= 2>/dev/null || true)"
      case "$cmd" in
        *".app/Contents/MacOS"*) cands+=("${cmd%%.app/Contents/MacOS*}.app") ;;
      esac
    done
  fi
  if command -v mdfind >/dev/null 2>&1; then
    local hits line
    hits="$(mdfind "kMDItemCFBundleIdentifier == 'ai.opencode.desktop'" 2>/dev/null | head -5)"
    while IFS= read -r line; do
      [[ -n "$line" && "$line" == *.app ]] && cands+=("$line")
    done <<< "$hits"
  fi
  local c
  for c in "${cands[@]}"; do
    if [[ -n "$c" && -f "$c/Contents/Resources/app.asar" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

APP="$(find_app)" || APP=""

# 数据目录:显式指定 > 默认位置的 appdir.txt > 应用目录下的 voice-data > 默认位置
if [[ -z "$STABLE" ]]; then
  if [[ -f "$DEFAULT_STABLE/appdir.txt" ]]; then
    STABLE="$DEFAULT_STABLE"
  elif [[ -n "$APP" && -d "$APP/voice-data" ]]; then
    STABLE="$APP/voice-data"
  else
    STABLE="$DEFAULT_STABLE"
  fi
fi

if [[ -z "$APP" ]]; then
  echo ""
  echo "没有自动找到 OpenCode.app。"
  read -r -p "请把 OpenCode.app 拖到本窗口后按回车(留空则跳过恢复): " input
  input="${input%\"}"; input="${input#\"}"; input="${input%\'}"; input="${input#\'}"
  if [[ -n "$input" && -f "$input/Contents/Resources/app.asar" ]]; then
    APP="$input"
    if [[ ! -f "$STABLE/appdir.txt" && -d "$APP/voice-data" ]]; then
      STABLE="$APP/voice-data"
    fi
  fi
fi

# 删除自动修复任务
PLIST="$HOME/Library/LaunchAgents/ai.opencode.voice.repair.plist"
launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
echo "已删除自动修复任务"

# 恢复原始 app.asar
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

# 删除数据目录
if [[ -d "$STABLE" ]]; then
  read -r -p "是否同时删除语音组件数据目录 $STABLE ?(约 300MB) [y/N] " answer
  if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    rm -rf "$STABLE" && echo "已删除数据目录"
  fi
fi
echo "卸载完成。"
read -n 1 -s -r -p "按任意键退出..."