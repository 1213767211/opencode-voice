#!/bin/bash
# ==oc-voice share== macOS 自动修复脚本(由 LaunchAgent 每10分钟调用一次)
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$DIR/install-mac.sh" --repair >/dev/null 2>&1 || true
exit 0
