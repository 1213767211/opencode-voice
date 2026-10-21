OpenCode 语音输入 安装说明(Linux)
===================================

【安装】
打开终端,cd 到本目录,运行:
  bash install-linux.sh
(装在 /opt 或 /usr/lib 时会自动使用 sudo 提权;也可直接 sudo bash install-linux.sh)

【会自动找到 OpenCode 吗?】
会搜索 /opt、/usr/lib、~/.local 等常见位置以及正在运行的 OpenCode。
找不到时,把 OpenCode 的安装目录拖进终端窗口后回车即可。
注意:AppImage 单文件版暂不支持,请使用 deb / tar 安装版。

【OpenCode 更新后麦克风没了怎么办?】
安装时已注册自动修复(systemd 用户定时器,无 systemd 时用 cron,每 10 分钟检查一次),
更新后会自动装回;若长时间未恢复,重新运行 install-linux.sh 即可。
从旧版本(v1.0.x)升级时,重新运行一次本安装包即可拿到修复。
自动修复需要用户桌面会话运行中。

【卸载】
  bash uninstall-linux.sh

【常见问题】
- 首次使用请允许 OpenCode 访问麦克风(系统设置→隐私/声音)。
- 语音识别完全离线运行,不会上传任何声音数据。
- 快捷键与别的软件冲突时,可编辑 ~/.local/share/opencode-voice/config.json
  里的 hotkey 后重启 OpenCode。
