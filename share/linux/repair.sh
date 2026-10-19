#!/bin/bash
# ==oc-voice share== Linux 自动修复脚本(由 systemd timer / cron 每10分钟调用一次)
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$DIR/install-linux.sh" --repair >/dev/null 2>&1 || true
exit 0
