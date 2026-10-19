#!/bin/bash
# ==oc-voice share== Linux 一键安装器
# 自动探测 OpenCode 安装目录,把语音输入模块打入 app.asar,并安装“更新修复”看护。
set -uo pipefail
cd "$(dirname "$0")"
PKG_ROOT="$(pwd)"

STABLE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode-voice"
LOG="$STABLE/install.log"
mkdir -p "$STABLE" 2>/dev/null

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
die() {
  log "错误: $*"
  echo ""
  echo "安装失败: $*"
  echo "请把以上内容截图发给分享者。"
  exit 1
}

REPAIR=0
[[ "${1:-}" == "--repair" ]] && REPAIR=1

find_app() {
  local cands=()
  if [[ -f "$STABLE/appdir.txt" ]]; then
    cands+=("$(cat "$STABLE/appdir.txt")")
  fi
  cands+=(
    "/opt/OpenCode" "/opt/opencode-desktop" "/opt/opencode" "/opt/OpenCode Desktop"
    "/usr/lib/opencode-desktop" "/usr/lib/opencode" "/usr/lib/OpenCode"
    "$HOME/.local/share/opencode-desktop" "$HOME/Applications/OpenCode" "$HOME/opt/opencode"
  )
  if command -v find >/dev/null 2>&1; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && cands+=("$(dirname "$(dirname "$line")")")
    done < <(find /opt /usr/local /usr/lib "$HOME/.local" "$HOME/Applications" -maxdepth 4 -name app.asar -path "*resources*" 2>/dev/null | head -10)
  fi
  local c
  for c in "${cands[@]}"; do
    if [[ -f "$c/resources/app.asar" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

find_exe() {
  local app="$1"
  local name
  for name in opencode-desktop opencode OpenCode; do
    if [[ -x "$app/$name" ]]; then echo "$app/$name"; return 0; fi
  done
  local f
  for f in "$app"/*; do
    if [[ -f "$f" && -x "$f" ]]; then
      case "$f" in
        *.so*|*.so|*.dat|*.pak|*.json|*.bin|*.desktop) ;;
        *) echo "$f"; return 0 ;;
      esac
    fi
  done
  return 1
}

APP="$(find_app)" || {
  if [[ $REPAIR == 1 ]]; then exit 0; fi
  echo "没有自动找到 OpenCode 安装目录。"
  echo "(如果你用的是 AppImage 单文件版,请换用 deb/tar 安装版后重试)"
  read -r -p "请把 OpenCode 的安装目录拖到本窗口后按回车: " input
  input="${input%\"}"; input="${input#\"}"; input="${input%\'}"; input="${input#\'}"
  if [[ ! -f "$input/resources/app.asar" ]]; then
    die "无效路径: $input"
  fi
  APP="$input"
}
log "OpenCode 目录: $APP"

RES="$APP/resources"
ASAR="$RES/app.asar"
NODE_EXE="$(find_exe "$APP")" || die "未在 $APP 找到可执行文件"
log "可执行文件: $NODE_EXE"

if [[ ! -w "$RES" ]]; then
  if [[ $REPAIR == 1 ]]; then
    log "无写入权限,跳过本次"
    exit 0
  fi
  if [[ "${OCV_SUDO:-0}" != "1" ]]; then
    log "需要管理员权限,正在提权..."
    exec sudo OCV_SUDO=1 bash "$0" "$@"
  fi
  die "仍然没有写入权限: $RES"
fi

# 关闭应用(修复模式不打扰用户,运行中则跳过)
if pgrep -f "$APP/" >/dev/null 2>&1; then
  if [[ $REPAIR == 1 ]]; then
    log "OpenCode 正在运行,跳过本次"
    exit 0
  fi
  log "正在关闭 OpenCode..."
  pkill -f "$APP/" >/dev/null 2>&1 || true
  sleep 3
  if pgrep -f "$APP/" >/dev/null 2>&1; then
    pkill -9 -f "$APP/" >/dev/null 2>&1 || true
    sleep 1
  fi
  if pgrep -f "$APP/" >/dev/null 2>&1; then
    die "无法关闭 OpenCode,请手动退出后重试"
  fi
fi

# 复制组件(仅首次/升级安装)
if [[ $REPAIR == 0 ]]; then
  log "正在复制语音组件到 $STABLE (约 300MB,请稍候)..."
  for part in patch engine model; do
    rm -rf "$STABLE/$part"
    cp -R "$PKG_ROOT/$part" "$STABLE/$part" || die "复制 $part 失败"
  done
  mkdir -p "$STABLE/tools"
  cp -R "$PKG_ROOT/tools/." "$STABLE/tools/" || die "复制工具失败"
  cp "$PKG_ROOT/install-linux.sh" "$STABLE/tools/install-linux.sh" 2>/dev/null || true
  if [[ ! -f "$STABLE/config.json" ]]; then
    echo '{"hotkey":"Control+Alt+Space","language":"auto","threads":0,"maxSeconds":120}' > "$STABLE/config.json"
  fi
  log "语音组件已就位"
fi

chmod +x "$STABLE"/engine/*/bin/sherpa-onnx-offline 2>/dev/null || true
chmod +x "$STABLE"/engine/bin/sherpa-onnx-offline 2>/dev/null || true

[[ -f "$STABLE/patch/out/voice/main.js" ]] || {
  if [[ $REPAIR == 1 ]]; then log "组件缺失,跳过"; exit 0; fi
  die "组件缺失: $STABLE/patch"
}

run_node() {
  local rc=0
  if ELECTRON_RUN_AS_NODE=1 "$NODE_EXE" "$@" 2>>"$LOG"; then
    return 0
  fi
  rc=$?
  if command -v node >/dev/null 2>&1; then
    node "$@" 2>>"$LOG"
    return $?
  fi
  return $rc
}

# 修复模式:已打过补丁就直接结束
if [[ $REPAIR == 1 ]]; then
  if run_node "$STABLE/tools/check-patched.mjs" "$ASAR" >/dev/null 2>&1; then
    exit 0
  fi
  log "检测到补丁缺失(可能刚更新),正在自动修复..."
fi

PATCH_ARGS=("$STABLE/tools/patch-app.mjs" --app-asar "$ASAR" --patch "$STABLE/patch")
[[ $REPAIR == 1 ]] && PATCH_ARGS+=(--refresh-backup)
log "正在打补丁..."
if ! run_node "${PATCH_ARGS[@]}"; then
  die "补丁应用失败,请把 $LOG 发给分享者"
fi
if ! run_node "$STABLE/tools/check-patched.mjs" "$ASAR" >/dev/null 2>&1; then
  die "校验失败:补丁未生效"
fi
log "补丁已生效"

echo "$APP" > "$STABLE/appdir.txt"

# 安装修复看护(systemd 用户级 timer,没有 systemd 时退回 cron)
WATCH_OK=0
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  UNIT_DIR="$HOME/.config/systemd/user"
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/opencode-voice-repair.service" <<UNIT_EOF
[Unit]
Description=OpenCode voice patch auto repair

[Service]
Type=oneshot
ExecStart=/bin/bash "$STABLE/tools/repair.sh"
UNIT_EOF
  cat > "$UNIT_DIR/opencode-voice-repair.timer" <<UNIT_EOF
[Unit]
Description=Check OpenCode voice patch every 10 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
Persistent=true

[Install]
WantedBy=timers.target
UNIT_EOF
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  if systemctl --user enable --now opencode-voice-repair.timer >/dev/null 2>&1; then
    WATCH_OK=1
    log "已安装自动修复任务(systemd,每10分钟检查一次)"
  fi
fi
if [[ $WATCH_OK == 0 ]] && command -v crontab >/dev/null 2>&1; then
  MARK="# opencode-voice-repair"
  (crontab -l 2>/dev/null | grep -v "$MARK"; echo "*/10 * * * * /bin/bash \"$STABLE/tools/repair.sh\" >/dev/null 2>&1 $MARK") | crontab - 2>/dev/null && {
    WATCH_OK=1
    log "已安装自动修复任务(cron,每10分钟检查一次)"
  }
fi
[[ $WATCH_OK == 0 ]] && log "提示: 自动修复任务创建失败,更新后如语音消失请重新运行安装包"

log "安装完成! 打开 OpenCode 后按 Ctrl+Alt+Space 或点输入框右下角麦克风开始说话。"
echo ""
echo "安装完成!"
echo "打开 OpenCode,点击输入框右下角的麦克风,或按快捷键 Ctrl+Alt+Space 即可语音输入。"
exit 0
