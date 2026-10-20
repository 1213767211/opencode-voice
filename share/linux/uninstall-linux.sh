#!/bin/bash
# ==oc-voice share== Linux 卸载:恢复原始 app.asar,删除看护任务与语音组件
set -uo pipefail

DEFAULT_STABLE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode-voice"
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
  cands+=(
    "/opt/OpenCode" "/opt/opencode-desktop" "/opt/opencode" "/opt/OpenCode Desktop"
    "/usr/lib/opencode-desktop" "/usr/lib/opencode" "/usr/lib/OpenCode"
    "$HOME/.local/share/opencode-desktop" "$HOME/Applications/OpenCode" "$HOME/opt/opencode"
  )
  if command -v pgrep >/dev/null 2>&1; then
    local p cmd
    for p in $(pgrep -f "resources/app.asar" 2>/dev/null); do
      cmd="$(ps -p "$p" -o command= 2>/dev/null || true)"
      case "$cmd" in
        */resources/app.asar*) cands+=("$(dirname "$(dirname "${cmd%% *}")")") ;;
      esac
    done
  fi
  if command -v find >/dev/null 2>&1; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && cands+=("$(dirname "$(dirname "$line")")")
    done < <(find /opt /usr/local /usr/lib "$HOME/.local" "$HOME/Applications" -maxdepth 4 -name app.asar -path "*resources*" 2>/dev/null | head -10)
  fi
  local c
  for c in "${cands[@]}"; do
    if [[ -n "$c" && -f "$c/resources/app.asar" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

APP="$(find_app)" || APP=""

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
  echo "没有自动找到 OpenCode 安装目录。"
  read -r -p "请把 OpenCode 的安装目录拖到本窗口后按回车(留空则跳过恢复): " input
  input="${input%\"}"; input="${input#\"}"; input="${input%\'}"; input="${input#\'}"
  if [[ -n "$input" && -f "$input/resources/app.asar" ]]; then
    APP="$input"
    if [[ ! -f "$STABLE/appdir.txt" && -d "$APP/voice-data" ]]; then
      STABLE="$APP/voice-data"
    fi
  fi
fi

# 删除自动修复任务
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now opencode-voice-repair.timer >/dev/null 2>&1 || true
  rm -f "$HOME/.config/systemd/user/opencode-voice-repair.service" "$HOME/.config/systemd/user/opencode-voice-repair.timer"
fi
if command -v crontab >/dev/null 2>&1; then
  (crontab -l 2>/dev/null | grep -v "opencode-voice-repair") | crontab - 2>/dev/null || true
fi
echo "已删除自动修复任务"

# 恢复原始 app.asar
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

# 删除数据目录
if [[ -d "$STABLE" ]]; then
  read -r -p "是否同时删除语音组件数据目录 $STABLE ?(约 300MB) [y/N] " answer
  if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    rm -rf "$STABLE" && echo "已删除数据目录"
  fi
fi
echo "卸载完成。"