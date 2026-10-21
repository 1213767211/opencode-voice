OpenCode 语音输入 安装说明(macOS)
===================================

【安装】
1. 解压后,双击“安装.command”
   若双击没反应或提示无法执行:打开“终端”,输入 bash 加一个空格,
   然后把“安装.command”文件拖进终端窗口,按回车。
2. 等待出现“安装完成!”(首次约 1~3 分钟)。
3. 打开 OpenCode,点击输入框右下角麦克风,或按 Ctrl+Alt+Space 说话。
   首次使用会弹出“OpenCode 想访问麦克风”,请点“允许”。

【关于签名与安全提示】
给 OpenCode 打完补丁后,原厂签名会失效,安装器会自动做本地重新签名(ad-hoc),
这是正常操作。如果 OpenCode 提示“已损坏,无法打开”,请在终端运行:
  xattr -dr com.apple.quarantine /Applications/OpenCode.app

【OpenCode 更新后麦克风没了怎么办?】
安装时已注册自动修复(LaunchAgent 每 10 分钟检查一次),更新后会自动装回;
若较长时间未恢复,重新运行一次“安装.command”即可。
从旧版本(v1.0.x)升级时,重新运行一次本安装包即可拿到修复。
注意:macOS 上 OpenCode 的内置自动更新可能因本地签名而失败,
如果更新失败,请到官网手动下载新版 OpenCode 安装,然后再运行一次本安装包。

【卸载】
双击“卸载.command”:恢复原始 OpenCode,并删除自动修复任务。

【常见问题】
- 语音识别完全离线运行,不会上传任何声音数据。
- 快捷键与别的软件冲突时,可编辑 ~/Library/Application Support/OpenCodeVoice/config.json
  里的 hotkey 后重启 OpenCode。
