#!/bin/bash
# ==oc-voice share== macOS 一键安装器
# 自动探测 OpenCode.app,把语音输入模块打入 app.asar,重新签名,并安装“更新修复”看护。
set -uo pipefail
cd "$(dirname "$0")"
PKG_ROOT="$(pwd)"

STABLE="$HOME/Library/Application Support/OpenCodeVoice"
LOG="$STABLE/install.log"
mkdir -p "$STABLE" 2>/dev/null

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
die() {
  log "错误: $*"
  echo ""
  echo "安装失败: $*"
  echo "请把以上内容截图发给分享者。"
  read -n 1 -s -r -p "按任意键退出..."
  exit 1
}

REPAIR=0
[[ "${1:-}" == "--repair" ]] && REPAIR=1

find_app() {
  local cands=()
  if [[ -f "$STABLE/appdir.txt" ]]; then
    cands+=("$(cat "$STABLE/appdir.txt")")
  fi
  cands+=("/Applications/OpenCode.app" "$HOME/Applications/OpenCode.app")
  if command -v mdfind >/dev/null 2>&1; then
    local hits
    hits="$(mdfind "kMDItemCFBundleIdentifier == 'ai.opencode.desktop'" 2>/dev/null | head -5)"
    while IFS= read -r line; do
      [[ -n "$line" && "$line" == *.app ]] && cands+=("$line")
    done <<< "$hits"
  fi
  local c
  for c in "${cands[@]}"; do
    if [[ -f "$c/Contents/Resources/app.asar" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

APP="$(find_app)" || {
  if [[ $REPAIR == 1 ]]; then exit 0; fi
  echo "没有自动找到 OpenCode.app。"
  read -r -p "请把 OpenCode.app 拖到本窗口后按回车: " input
  input="${input%\"}"; input="${input#\"}"; input="${input%\'}"; input="${input#\'}"
  if [[ ! -f "$input/Contents/Resources/app.asar" ]]; then
    die "无效路径: $input"
  fi
  APP="$input"
}
log "OpenCode.app: $APP"

RES="$APP/Contents/Resources"
ASAR="$RES/app.asar"
NODE_EXE="$APP/Contents/MacOS/OpenCode"
[[ -f "$NODE_EXE" ]] || die "未找到可执行文件: $NODE_EXE"

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
if pgrep -f "$APP/Contents/MacOS" >/dev/null 2>&1; then
  if [[ $REPAIR == 1 ]]; then
    log "OpenCode 正在运行,跳过本次"
    exit 0
  fi
  log "正在关闭 OpenCode..."
  osascript -e 'quit app "OpenCode"' >/dev/null 2>&1 || true
  sleep 2
  pkill -f "$APP/Contents/MacOS" >/dev/null 2>&1 || true
  sleep 1
  if pgrep -f "$APP/Contents/MacOS" >/dev/null 2>&1; then
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
  cp "$PKG_ROOT/install-mac.sh" "$STABLE/tools/install-mac.sh" 2>/dev/null || true
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

# 修复模式:已打过补丁就直接结束
if [[ $REPAIR == 1 ]]; then
  if ELECTRON_RUN_AS_NODE=1 "$NODE_EXE" "$STABLE/tools/check-patched.mjs" "$ASAR" >/dev/null 2>&1; then
    exit 0
  fi
  log "检测到补丁缺失(可能刚更新),正在自动修复..."
fi

PATCH_ARGS=("$STABLE/tools/patch-app.mjs" --app-asar "$ASAR" --patch "$STABLE/patch")
[[ $REPAIR == 1 ]] && PATCH_ARGS+=(--refresh-backup)
log "正在打补丁..."
if ! ELECTRON_RUN_AS_NODE=1 "$NODE_EXE" "${PATCH_ARGS[@]}"; then
  die "补丁应用失败,请把 $LOG 发给分享者"
fi
if ! ELECTRON_RUN_AS_NODE=1 "$NODE_EXE" "$STABLE/tools/check-patched.mjs" "$ASAR" >/dev/null 2>&1; then
  die "校验失败:补丁未生效"
fi
log "补丁已生效"

# 重新签名(修改 app.asar 后必须重新签名,否则 macOS 会拒绝启动)
log "正在重新签名..."
if ! codesign --force --deep --preserve-metadata=entitlements,requirements,flags -s - "$APP" 2>>"$LOG"; then
  log "保留元数据签名失败,尝试普通签名..."
  codesign --force --deep -s - "$APP" 2>>"$LOG" || log "提示: 签名失败,如果应用打不开请反馈"
fi
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$STABLE" >/dev/null 2>&1 || true
log "签名与去隔离完成"

echo "$APP" > "$STABLE/appdir.txt"

# 安装修复看护(LaunchAgent)
PLIST="$HOME/Library/LaunchAgents/ai.opencode.voice.repair.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>ai.opencode.voice.repair</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$STABLE/tools/repair.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>600</integer>
</dict>
</plist>
PLIST_EOF
launchctl unload "$PLIST" >/dev/null 2>&1 || true
if launchctl load "$PLIST" >/dev/null 2>&1; then
  log "已安装自动修复任务(每10分钟检查一次,更新后自动还原语音功能)"
else
  log "提示: 自动修复任务注册失败,更新后如语音消失请重新运行安装包"
fi

log "安装完成! 打开 OpenCode 后按 Ctrl+Alt+Space 或点输入框右下角麦克风开始说话。"
echo ""
echo "安装完成!"
echo "打开 OpenCode,点击输入框右下角的麦克风,或按快捷键 Ctrl+Alt+Space 即可语音输入。"
echo "(首次使用会弹出麦克风权限请求,请点“允许”)"
read -n 1 -s -r -p "按任意键关闭本窗口..."
exit 0
