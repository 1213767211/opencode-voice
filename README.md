# OpenCode 语音输入插件(离线版)

*在心为志,发言为诗。*

<p align="center"><img src="assets/logo.svg" alt="OpenCode 语音输入插件" width="640"></p>

为 [OpenCode Desktop](https://opencode.ai) 添加**离线语音输入**能力:按下快捷键说出你想说的话,语音在本机识别成文字,自动填入对话框。全部离线运行,不联网、不上传任何语音数据。

> 非官方社区补丁,仅供个人使用。安装包会自动备份原始文件,支持一键卸载还原。

## 功能特性

- **离线识别**:基于 sherpa-onnx + 内置中文语音识别模型,音频不出本机
- **一键说话**:默认快捷键 `Ctrl + Alt + Space`,再按一次结束并转写;识别结果自动插入当前输入框
- **智能结束**:说完静音约 1.6 秒自动结束录音并开始转写
- **内嵌状态提示**:录音时输入框旁显示"正在聆听 / 识别中…"胶囊,与界面主题融为一体,无悬浮窗打扰
- **自动修复**:OpenCode 自动更新后会后台自动重新打补丁,不用重装
- **不残留后台进程**:关闭主窗口后进程会真正退出(修复 v1.1.0 之前「关掉窗口后再点图标没反应」的问题)
- **一键卸载**:随时还原为原始版 OpenCode

## 效果展示

| 待机 | 正在聆听 | 识别中… |
| :---: | :---: | :---: |
| ![待机](assets/shot-idle.png) | ![正在聆听](assets/shot-listening.png) | ![识别中](assets/shot-transcribing.png) |

按 `Ctrl + Alt + Space` 开始说话,说完静音约 1.6 秒自动结束,识别结果直接填入输入框;也可以随时点击输入框右侧的麦克风按钮开始/结束。

## 下载

到本仓库的 [Releases](../../releases) 页面下载对应系统的压缩包:

| 系统 | 安装包 | 大小 | 支持范围 |
| --- | --- | --- | --- |
| Windows 10/11 | `oc-voice-windows-x64.zip` | 约 180 MB | x64 |
| macOS | `oc-voice-macos-universal.zip` | 约 199 MB | Intel / Apple Silicon 通用 |
| Linux | `oc-voice-linux-x64.zip` | 约 184 MB | x64(glibc,不支持 AppImage) |

适用版本:OpenCode Desktop **v1.19.x**(其他版本可能也能用,未逐一验证)。

## 安装

> 安装前请先退出 OpenCode。安装器会自动探测 OpenCode 安装目录,无需手动选择文件夹。

**Windows**:解压后双击 `安装.bat`(如弹 UAC 请允许)。

**macOS**:解压后双击 `安装.command`。首次打开若被系统拦截,请右键 → 打开,或终端执行 `bash 安装.command`。

**Linux**:解压后执行 `bash install-linux.sh`(会提示输入 sudo 密码以提权)。

安装器会自动完成:

1. 找到 OpenCode 的安装目录
2. 把语音组件(引擎 + 模型)复制到用户数据目录
3. 给 OpenCode 打上语音补丁(自动备份原始文件)
4. 注册后台修复任务(OpenCode 更新后自动恢复补丁)

安装完成后重新打开 OpenCode,按 `Ctrl + Alt + Space` 开始说话。

## 卸载

- Windows:双击 `卸载.bat`
- macOS:双击 `卸载.command`
- Linux:执行 `bash uninstall-linux.sh`

卸载会恢复原始文件并移除后台任务。语音组件数据可一并删除。

## 常见问题

**按快捷键没反应?**
确认安装完成(安装器最后会显示成功信息),然后完全退出并重新打开 OpenCode。再不行请看 OpenCode 安装目录 `resources` 下是否存在 `app.asar.bak-voice`(存在说明补丁已装)。

**macOS 提示"无法验证开发者"?**
本插件使用 ad-hoc 签名。右键 → 打开,或终端执行 `bash 安装.command`。

**OpenCode 更新后语音失灵?**
后台修复任务会在检测到 `app.asar` 变化时自动重新打补丁(Windows 由启动时的看护脚本监视,间隔约 10 分钟;macOS / Linux 由 LaunchAgent / systemd timer 每 10 分钟检查),更新后稍等片刻重启 OpenCode 即可。也可以手动重跑一次安装器(重复安装是安全的)。

**杀毒软件报警?**
安装器是 PowerShell 脚本(做了签名保护壳),可能被部分杀软误报。放行即可,脚本内容全部开源在本仓库。

**点了图标没反应 / 关掉窗口后再也打不开?**
这是 v1.1.0 之前版本的已知问题:关闭主窗口时语音悬浮窗仍留在后台,进程不退出并占着单实例锁,于是再点 `OpenCode.exe` 时新进程会被静默退出。升级到 v1.1.0 及以后即可(安装器会重打补丁);临时应急可以在任务管理器里结束所有 `OpenCode` 进程后再打开。

**语音识别不准 / 没识别出来?**
环境嘈杂或说话太轻时可能识别为空,建议靠近麦克风、正常语速。静音会自动跳过,不会插入空文本。

**支持其他语言吗?**
当前内置中文模型,其他语言暂未测试。

## 数据目录

| 系统 | 路径 |
| --- | --- |
| Windows | `%LOCALAPPDATA%\OpenCodeVoice` |
| macOS | `~/Library/Application Support/OpenCodeVoice` |
| Linux | `~/.local/share/opencode-voice` |

包含语音引擎、模型、配置和安装日志。卸载后可直接删除。

## 技术说明

- 语音引擎:[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) v1.13.8(Windows / macOS / Linux 三平台)
- 识别模型:SenseVoice(中/英/日/韩/粤),int8 量化(约 228 MB,随包分发,纯离线)
- 补丁方式:解包 `app.asar` → 注入 `out/voice` 语音模块并追加入口代码 → 重新打包,原文件备份为 `app.asar.bak-voice`
- 修复机制:Windows 登录时启动看护脚本(`Startup\OpenCodeVoiceWatch.vbs`)、macOS LaunchAgent / Linux systemd 用户定时器,发现 `app.asar` 被替换(更新)时自动重打补丁

## 开发与构建(给想改的人)

### 目录结构

| 路径 | 说明 |
| --- | --- |
| `patch/out/voice/` | 语音模块源码:主进程逻辑(`main.js`)、输入框麦克风按钮与状态胶囊(`button-inject.js`)、录音窗口(`overlay.js` / `overlay.html`) |
| `patch/append-content.js` | 追加到 `out/main/index.js` 末尾的入口代码 |
| `tools/patch-app.mjs` | 打补丁工具:解包 asar → 注入源码 → 重打包,支持备份/回滚/校验 |
| `tools/check-patched.mjs` | 检查某个 `app.asar` 是否已包含语音模块(退出码 0=已打) |
| `share/` | 三个平台的一键安装 / 卸载 / 修复脚本(最终用户使用的就是这些) |
| `build/build-share.ps1` | 组装三平台发布包并打 zip(Windows 上运行,内附路径为作者本机示例) |
| `dev/` | 开发机部署脚本(源码直接部署到本机 OpenCode,路径可按需修改) |

### 工作原理

1. `patch-app.mjs` 解包 OpenCode 的 `resources/app.asar`;
2. 把 `patch/out/voice/` 复制进 `out/voice/`,并把 `append-content.js` 追加到 `out/main/index.js`(带 `// ==oc-voice-appended==` 标记,可重复注入);
3. 重打包并替换,原文件备份为 `app.asar.bak-voice`;
4. 应用启动后语音模块注册全局快捷键、录音、调用 `sherpa-onnx-offline` 识别并把文字插入输入框;
5. `share/` 安装器负责探测安装目录、复制引擎/模型、打补丁、注册后台修复任务(OpenCode 更新后自动重打)。

### 自己打补丁 / 重新打包

```bash
# 依赖:node,先执行 npm i @electron/asar(tools/package.json 已声明)
node tools/patch-app.mjs --app-asar "/path/to/resources/app.asar" --patch ./patch
```

```powershell
# 重新组装三平台发布包(需先准备引擎与模型,脚本内路径按实际情况修改)
powershell -ExecutionPolicy Bypass -File build\build-share.ps1
```

### 引擎与模型来源

- 引擎 sherpa-onnx v1.13.8(发布包已内置):
  - Windows:`https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-win-x64-shared-MT-Release.tar.bz2`
  - Linux:`.../v1.13.8/sherpa-onnx-v1.13.8-linux-x64-shared.tar.bz2`
  - macOS:`.../v1.13.8/sherpa-onnx-v1.13.8-osx-universal2-shared.tar.bz2`
- 模型 SenseVoice(zh/en/ja/ko/yue):`model.int8.onnx`(239,239,841 字节)+ `tokens.txt`
  - 来源:`https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`(国内可用 `https://hf-mirror.com/` 相同路径)

### 自定义

快捷键 / 语言 / 线程数 / 单次录音上限等改用户数据目录下的 `config.json`(见上「数据目录」):

```json
{ "hotkey": "Control+Alt+Space", "language": "auto", "threads": 0, "maxSeconds": 120 }
```

界面相关:录音胶囊在 `patch/out/voice/button-inject.js`(`buildChip` / `updateChip`),样式复制自 OpenCode 自带的 `button-v2` 组件,自动跟随主题。

## 更新记录

### v1.1.0
- **修复**:关闭主窗口后语音悬浮窗残留导致进程不退出、单实例锁被占用,表现为「再点 OpenCode.exe 完全没反应」。现在关闭最后一个窗口时会同步销毁悬浮窗并退出进程
- **修复**:再次启动 OpenCode 时会把已有的主窗口还原并置前,不再出现「进程在但没窗口」
- **改进**:补丁带版本号(`OCV_PATCH_VERSION`),安装器与修复任务能识别旧补丁并自动升级重打
- **改进**:Windows 自动修复改为登录时的文件监视看护脚本,不再每 10 分钟无条件运行,也绝不会主动关闭 OpenCode

### v1.0.0
- 首个公开版本:离线语音识别、快捷键 / 麦克风按钮、内嵌状态胶囊、三平台一键安装与卸载

## 许可证

本项目基于 [MIT License](LICENSE) 开源:可自由使用、修改、分发,保留版权声明即可。

## 社区认可
[LINUX DO](https://linux.do/) --「新的理想型社区」，本项目在 LINUX DO 社区进行开源推广，感谢佬友们的支持与反馈。
## 免责声明

本项目为非官方补丁,与 OpenCode 官方无关。修改应用文件存在一定风险(已提供备份与一键还原)。使用即表示自行承担风险。
