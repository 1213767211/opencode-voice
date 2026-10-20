// ==oc-voice== 语音输入模块(由 voice-mod 安装器注入,请勿手动修改 asar 内文件)
import { app, BrowserWindow, clipboard, globalShortcut, ipcMain, Notification, screen } from "electron";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const CH = {
  start: "ocv:start",
  stop: "ocv:stop",
  state: "ocv:state",
  ready: "ocv:ready",
  audio: "ocv:audio",
  cancel: "ocv:cancel",
  error: "ocv:error",
  hover: "ocv:hover",
};

const DEFAULT_CONFIG = {
  hotkey: "Control+Alt+Space",
  language: "auto",
  threads: 0,
  maxSeconds: 120,
  dataDir: null,
  engineExe: null,
  model: null,
  tokens: null,
};

function defaultDataDir() {
  try {
    const exeDir = path.dirname(app.getPath("exe"));
    const candidates = [path.join(exeDir, "voice-data"), path.join(path.dirname(exeDir), "voice-data")];
    for (const dir of candidates) {
      if (fs.existsSync(path.join(dir, "engine")) || fs.existsSync(path.join(dir, "config.json"))) {
        return dir;
      }
    }
  } catch {}
  const home = os.homedir() || "";
  if (process.platform === "win32") {
    const base = process.env.LOCALAPPDATA || path.join(home, "AppData", "Local");
    return path.join(base, "OpenCodeVoice");
  }
  if (process.platform === "darwin") {
    return path.join(home, "Library", "Application Support", "OpenCodeVoice");
  }
  return path.join(home, ".local", "share", "opencode-voice");
}

let dataDir = process.env.OPENCODE_VOICE_DIR || defaultDataDir();
let config = { ...DEFAULT_CONFIG };

let logFile = null;
function log(...parts) {
  const line =
    new Date().toISOString() +
    " [oc-voice] " +
    parts
      .map((p) => {
        if (typeof p === "string") return p;
        try {
          return JSON.stringify(p);
        } catch {
          return String(p);
        }
      })
      .join(" ");
  try {
    if (!logFile) {
      const dir = path.join(dataDir, "logs");
      fs.mkdirSync(dir, { recursive: true });
      logFile = path.join(dir, "voice.log");
    }
    try {
      if (fs.existsSync(logFile) && fs.statSync(logFile).size > 2 * 1024 * 1024) {
        fs.writeFileSync(logFile, "");
      }
    } catch {}
    fs.appendFileSync(logFile, line + "\r\n");
  } catch {}
  // eslint-disable-next-line no-console
  try {
    console.log(line);
  } catch {}
}

function loadConfig() {
  const file = path.join(dataDir, "config.json");
  try {
    if (fs.existsSync(file)) {
      const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
      config = { ...config, ...parsed };
    }
  } catch (error) {
    log("failed to read config", String(error && error.message));
  }
  if (config.dataDir && typeof config.dataDir === "string") {
    dataDir = config.dataDir;
    try {
      const file2 = path.join(dataDir, "config.json");
      if (fs.existsSync(file2)) {
        const parsed2 = JSON.parse(fs.readFileSync(file2, "utf8"));
        config = { ...config, ...parsed2 };
      }
    } catch {}
  }
}

function resolveEngine() {
  const model = config.model || path.join(dataDir, "model", "model.int8.onnx");
  const tokens = config.tokens || path.join(dataDir, "model", "tokens.txt");
  const exeNames =
    process.platform === "win32"
      ? ["sherpa-onnx-offline.exe", "sherpa-onnx-offline"]
      : ["sherpa-onnx-offline", "sherpa-onnx-offline.exe"];
  const candidates = [];
  if (config.engineExe) candidates.push(config.engineExe);
  const engineRoot = path.join(dataDir, "engine");
  try {
    for (const entry of fs.readdirSync(engineRoot, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        for (const name of exeNames) {
          candidates.push(path.join(engineRoot, entry.name, "bin", name));
        }
      }
    }
  } catch {}
  for (const name of exeNames) {
    candidates.push(path.join(engineRoot, "bin", name));
  }
  for (const exe of candidates) {
    if (fs.existsSync(exe)) return { exe, model, tokens };
  }
  return null;
}

function parseAsrOutput(buffer) {
  const lines = buffer.toString("utf8").split(/\r?\n/);
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i].trim();
    if (!line.startsWith("{")) continue;
    try {
      const parsed = JSON.parse(line);
      if (typeof parsed.text === "string") return parsed.text;
    } catch {}
  }
  return null;
}

function transcribe(wavPath) {
  return new Promise((resolve, reject) => {
    const engine = resolveEngine();
    if (!engine) return reject(new Error("语音引擎未安装,请重新运行语音输入安装包"));
    if (!fs.existsSync(engine.model)) return reject(new Error("语音模型缺失: " + engine.model));
    if (!fs.existsSync(engine.tokens)) return reject(new Error("模型词表缺失: " + engine.tokens));
    const cpus = (os.cpus() || []).length || 4;
    const threads = Number(config.threads) > 0 ? Number(config.threads) : Math.max(2, Math.min(8, cpus));
    const args = [
      `--tokens=${engine.tokens}`,
      `--sense-voice-model=${engine.model}`,
      `--num-threads=${threads}`,
      "--sense-voice-use-itn=true",
    ];
    if (config.language && config.language !== "auto") args.push(`--sense-voice-language=${config.language}`);
    args.push(wavPath);
    const started = Date.now();
    const child = spawn(engine.exe, args, {
      cwd: path.dirname(engine.exe),
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
      env: (() => {
        const env = { ...process.env };
        try {
          const libDir = path.join(path.dirname(engine.exe), "..", "lib");
          if (process.platform === "linux") {
            env.LD_LIBRARY_PATH = libDir + (env.LD_LIBRARY_PATH ? ":" + env.LD_LIBRARY_PATH : "");
          } else if (process.platform === "darwin") {
            env.DYLD_LIBRARY_PATH = libDir + (env.DYLD_LIBRARY_PATH ? ":" + env.DYLD_LIBRARY_PATH : "");
          }
        } catch {}
        return env;
      })(),
    });
    const outChunks = [];
    const errChunks = [];
    const timer = setTimeout(() => {
      try {
        child.kill();
      } catch {}
      reject(new Error("识别超时"));
    }, 60000);
    child.stdout.on("data", (chunk) => outChunks.push(chunk));
    child.stderr.on("data", (chunk) => errChunks.push(chunk));
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(new Error("无法启动语音引擎: " + error.message));
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      const out = Buffer.concat(outChunks);
      const err = Buffer.concat(errChunks).toString("utf8");
      const text = parseAsrOutput(out);
      log("transcribe done", { code, ms: Date.now() - started, text: text === null ? "<parse-failed>" : text });
      if (text === null) {
        log("transcribe output", out.toString("utf8").slice(-600), err.slice(-300));
        reject(new Error("识别失败"));
        return;
      }
      resolve(text);
    });
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function insertIntoWindow(target, text) {
  if (!target || target.isDestroyed()) return { ok: false, reason: "no-window" };
  try {
    if (target.isMinimized()) target.restore();
    target.show();
    target.focus();
  } catch {}
  await sleep(200);
  const wc = target.webContents;
  try {
    wc.focus();
  } catch {}
  const probe = `(() => {
    const el = document.querySelector('[data-component="prompt-input"]');
    if (!el) {
      const ae = document.activeElement;
      const editable = !!(ae && (ae.isContentEditable || /^(TEXTAREA|INPUT)$/.test(ae.tagName || "")));
      return { found: false, editable };
    }
    try {
      const sel = window.getSelection();
      let keep = false;
      try { keep = !!(sel && sel.rangeCount > 0 && el.contains(sel.getRangeAt(0).startContainer)); } catch {}
      if (!keep) {
        const range = document.createRange();
        range.selectNodeContents(el);
        range.collapse(false);
        sel.removeAllRanges();
        sel.addRange(range);
      }
      el.focus();
      return { found: true, before: el.innerText };
    } catch (error) {
      return { found: false, editable: false, error: String(error && error.message) };
    }
  })()`;
  let info = null;
  try {
    info = await wc.executeJavaScript(probe, true);
  } catch (error) {
    log("probe failed", String(error && error.message));
  }
  if (info && info.found) {
    const before = info.before;
    try {
      await wc.executeJavaScript(`document.execCommand('insertText', false, ${JSON.stringify(text)})`, true);
    } catch {}
    await sleep(180);
    let after = null;
    try {
      after = await wc.executeJavaScript(
        `(() => { const el = document.querySelector('[data-component="prompt-input"]'); return el ? el.innerText : null; })()`,
        true,
      );
    } catch {}
    if (typeof after === "string" && after !== before) return { ok: true, method: "execCommand" };
    try {
      wc.insertText(text);
    } catch {}
    await sleep(180);
    try {
      after = await wc.executeJavaScript(
        `(() => { const el = document.querySelector('[data-component="prompt-input"]'); return el ? el.innerText : null; })()`,
        true,
      );
    } catch {}
    if (typeof after === "string" && after !== before) return { ok: true, method: "insertText" };
    return { ok: false, reason: "insert-failed" };
  }
  if (info && info.editable) {
    try {
      wc.insertText(text);
      return { ok: true, method: "insertText-unverified" };
    } catch {}
  }
  return { ok: false, reason: "no-input" };
}

let overlay = null;
let overlayReadyResolver = null;
let overlayReadyPromise = null;

let buttonInjectSource = null;
function getButtonInjectSource() {
  if (buttonInjectSource === null) {
    try {
      buttonInjectSource = fs.readFileSync(path.join(import.meta.dirname, "button-inject.js"), "utf8");
    } catch (error) {
      log("failed to read button-inject.js", String(error && error.message));
      buttonInjectSource = "";
    }
  }
  return buttonInjectSource;
}

function updateMicState(state) {
  const source = `window.__ocvSetState && window.__ocvSetState(${JSON.stringify(state)});`;
  for (const win of BrowserWindow.getAllWindows()) {
    if (!win || win.isDestroyed() || win.__ocVoice) continue;
    try {
      win.webContents.executeJavaScript(source, true).catch(() => {});
    } catch {}
  }
}

function attachMicButton(win) {
  if (!win || win.__ocVoice || win.__ocvAttached) return;
  win.__ocvAttached = true;
  const wc = win.webContents;
  wc.on("console-message", (...args) => {
    for (const arg of args) {
      let message = null;
      if (typeof arg === "string") message = arg;
      else if (arg && typeof arg.message === "string") message = arg.message;
      if (message && message.indexOf("__OCV_ACTION__:toggle") >= 0) {
        void toggle();
        return;
      }
      if (message && message.indexOf("__OCV_LOG__:") === 0) {
        try {
          log("ui", JSON.parse(message.slice("__OCV_LOG__:".length)));
        } catch {}
        return;
      }
    }
  });
  const inject = () => {
    const src = getButtonInjectSource();
    if (!src) return;
    wc.executeJavaScript(src, true)
      .then((count) => {
        log("mic button injected", { count });
        const current = mode === "listening" ? "listening" : mode === "transcribing" ? "transcribing" : "idle";
        return wc.executeJavaScript(`window.__ocvSetState && window.__ocvSetState(${JSON.stringify(current)});`, true);
      })
      .catch((error) => {
        log("mic button inject failed", String(error && error.message));
      });
  };
  try {
    inject();
  } catch {}
  wc.on("did-finish-load", inject);
}

app.on("browser-window-created", (_event, win) => {
  attachMicButton(win);
});

function ensureOverlay() {
  if (overlay && !overlay.isDestroyed()) return overlay;
  overlayReadyPromise = new Promise((resolve) => {
    overlayReadyResolver = resolve;
  });
  overlay = new BrowserWindow({
    width: 384,
    height: 76,
    frame: false,
    transparent: true,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    show: false,
    hasShadow: false,
    backgroundColor: "#00000000",
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      sandbox: false,
      spellcheck: false,
      backgroundThrottling: false,
      partition: "oc-voice-overlay",
    },
  });
  overlay.__ocVoice = true;
  try {
    overlay.setAlwaysOnTop(true, "screen-saver");
  } catch {}
  try {
    overlay.setIgnoreMouseEvents(true, { forward: true });
  } catch {}
  const ses = overlay.webContents.session;
  try {
    ses.setPermissionRequestHandler((wc, permission, callback) => {
      callback(wc === overlay.webContents && permission === "media");
    });
    ses.setPermissionCheckHandler((wc, permission) => permission === "media" && wc === overlay.webContents);
  } catch {}
  overlay.webContents.on("render-process-gone", (_event, details) => {
    log("overlay renderer gone", details);
    try {
      if (overlay && !overlay.isDestroyed()) overlay.destroy();
    } catch {}
    overlay = null;
    if (mode === "listening") {
      mode = "idle";
      targetWindow = null;
    }
  });
  overlay.on("closed", () => {
    overlay = null;
    overlayReadyResolver = null;
    if (mode === "listening") resetToIdle();
  });
  overlay.loadFile(path.join(import.meta.dirname, "overlay.html"));
  return overlay;
}

function positionOverlay() {
  if (!overlay || overlay.isDestroyed()) return;
  try {
    const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
    const area = display.workArea;
    const [width, height] = overlay.getSize();
    overlay.setPosition(
      Math.round(area.x + (area.width - width) / 2),
      Math.round(area.y + area.height - height - 80),
    );
  } catch {}
}

let fadeTimer = null;
function fadeTo(win, target, done) {
  if (!win || win.isDestroyed()) return;
  try {
    if (fadeTimer) clearInterval(fadeTimer);
    let opacity = win.getOpacity();
    fadeTimer = setInterval(() => {
      if (!win || win.isDestroyed()) {
        clearInterval(fadeTimer);
        fadeTimer = null;
        return;
      }
      const delta = target > opacity ? 0.2 : -0.25;
      opacity = target > opacity ? Math.min(target, opacity + delta) : Math.max(target, opacity + delta);
      try {
        win.setOpacity(opacity);
      } catch {}
      if (opacity === target) {
        clearInterval(fadeTimer);
        fadeTimer = null;
        if (done) done();
      }
    }, 16);
  } catch {}
}

let mode = "idle"; // idle | listening | transcribing
let audioEventCount = 0;
let targetWindow = null;
let lastMainWindow = null;
let maxTimer = null;

app.on("browser-window-focus", (_event, win) => {
  if (win && !win.__ocVoice) lastMainWindow = win;
});

function getTargetWindow() {
  const focused = BrowserWindow.getFocusedWindow();
  if (focused && !focused.__ocVoice) return focused;
  if (lastMainWindow && !lastMainWindow.isDestroyed()) return lastMainWindow;
  const win = BrowserWindow.getAllWindows().find((w) => !w.__ocVoice && !w.isDestroyed());
  return win || null;
}

function sendToOverlay(channel, ...args) {
  if (overlay && !overlay.isDestroyed()) {
    try {
      overlay.webContents.send(channel, ...args);
    } catch {}
  }
}

function setOverlayState(state, message) {
  sendToOverlay(CH.state, { state, message: message || "" });
  updateMicState(state === "listening" || state === "transcribing" ? state : "idle");
}

function hideOverlay(delayMs) {
  const win = overlay;
  if (!win || win.isDestroyed()) return;
  setTimeout(
    () => {
      if (!win || win.isDestroyed()) return;
      fadeTo(win, 0, () => {
        try {
          if (!win.isDestroyed()) win.hide();
        } catch {}
      });
    },
    Math.max(0, delayMs || 0),
  );
}

function resetToIdle() {
  mode = "idle";
  targetWindow = null;
  if (maxTimer) {
    clearTimeout(maxTimer);
    maxTimer = null;
  }
}

function finishWithState(state, message, hideDelay) {
  setOverlayState(state, message);
  resetToIdle();
  hideOverlay(hideDelay);
}

function startListening() {
  if (mode !== "idle") return;
  mode = "listening";
  targetWindow = getTargetWindow();
  ensureOverlay();
  sendToOverlay(CH.start);
  updateMicState("listening");
  log("listening", { target: targetWindow ? targetWindow.getTitle() : null });
  if (maxTimer) clearTimeout(maxTimer);
  const maxSeconds = Number(config.maxSeconds) > 0 ? Number(config.maxSeconds) : 120;
  maxTimer = setTimeout(() => {
    log("max duration reached, stopping");
    stopListening();
  }, maxSeconds * 1000);
}

function stopListening() {
  if (mode !== "listening") return;
  if (maxTimer) {
    clearTimeout(maxTimer);
    maxTimer = null;
  }
  if (overlay && !overlay.isDestroyed()) sendToOverlay(CH.stop);
  else resetToIdle();
}

async function handleAudio(arrayBuffer, meta) {
  audioEventCount++;
  if (mode === "idle") return;
  mode = "transcribing";
  setOverlayState("transcribing", "识别中…");
  const bytes = Buffer.from(new Uint8Array(arrayBuffer));
  const duration = (meta && meta.duration) || (bytes.length - 44) / 2 / 16000;
  const rms = (meta && meta.rms) || 0;
  log("audio received", { bytes: bytes.length, duration: Number(duration.toFixed(2)), rms: Number(rms.toFixed(4)) });
  if (duration < 0.35 || rms < 0.006) {
    finishWithState("error", "没有检测到声音", 2200);
    return;
  }
  let text = "";
  try {
    const dir = path.join(dataDir, "tmp");
    fs.mkdirSync(dir, { recursive: true });
    const wavPath = path.join(dir, "rec.wav");
    fs.writeFileSync(wavPath, bytes);
    text = await transcribe(wavPath);
  } catch (error) {
    log("transcribe error", String(error && error.message));
    finishWithState("error", (error && error.message) || "识别失败", 3600);
    return;
  }
  text = String(text || "").trim();
  if (!text || /^[，。、！？,.!?;；:：\s]+$/.test(text)) {
    finishWithState("error", "没听清,请再试一次", 2600);
    return;
  }
  const target = targetWindow;
  const result = await insertIntoWindow(target, text);
  log("insert result", result);
  if (result.ok) {
    finishWithState("done", "已输入", 750);
    return;
  }
  try {
    clipboard.writeText(text);
  } catch {}
  finishWithState("error", "未找到输入框,文字已复制到剪贴板", 3600);
}

function cancelListening() {
  resetToIdle();
  setOverlayState("cancelled", "");
  hideOverlay(0);
}

async function toggle() {
  if (mode === "idle") {
    startListening();
    return;
  }
  if (mode === "listening") {
    stopListening();
    return;
  }
}

function registerHotkey() {
  const hotkey = config.hotkey || DEFAULT_CONFIG.hotkey;
  let ok = false;
  try {
    ok = globalShortcut.register(hotkey, () => {
      void toggle();
    });
  } catch (error) {
    log("hotkey register threw", String(error && error.message));
  }
  log("hotkey", { hotkey, registered: ok });
  if (!ok) {
    try {
      new Notification({
        title: "OpenCode 语音输入",
        body: `快捷键 ${hotkey} 注册失败,可能与其他软件冲突。可修改 ${path.join(dataDir, "config.json")} 中的 hotkey 后重启应用。`,
      }).show();
    } catch {}
  }
  return ok;
}

async function runSelfTest() {
  const results = {};
  try {
    await sleep(9000);
    const windows = BrowserWindow.getAllWindows();
    results.windows = windows.map((win) => ({
      title: win.getTitle(),
      overlay: !!win.__ocVoice,
      url: (() => {
        try {
          return win.webContents.getURL();
        } catch {
          return null;
        }
      })(),
    }));
    const main = windows.find((win) => !win.__ocVoice && !win.isDestroyed());
    results.mainWindow = !!main;
    const ov = ensureOverlay();
    let readyOk = false;
    try {
      const readyWait = overlayReadyPromise
        ? overlayReadyPromise.then(() => {
            readyOk = true;
          })
        : Promise.resolve();
      await Promise.race([readyWait, sleep(5000)]);
    } catch {}
    results.overlayCreated = !!(ov && !ov.isDestroyed());
    results.overlayReady = readyOk;
    const engine = resolveEngine();
    results.engine = engine;
    const testWav = process.env.OC_VOICE_TEST_WAV || path.join(dataDir, "tmp", "test-zh.wav");
    results.testWav = testWav;
    if (fs.existsSync(testWav)) {
      const started = Date.now();
      try {
        results.text = await transcribe(testWav);
        results.transcribeMs = Date.now() - started;
      } catch (error) {
        results.transcribeError = String(error && error.message);
      }
    } else {
      results.transcribeError = "test wav not found";
    }
    if (main && results.text) {
      results.insert = await insertIntoWindow(main, results.text);
      await sleep(400);
      try {
        results.editorAfter = await main.webContents.executeJavaScript(
          `(() => { const el = document.querySelector('[data-component="prompt-input"]'); return el ? el.innerText.slice(0, 300) : null; })()`,
          true,
        );
      } catch (error) {
        results.editorAfterError = String(error && error.message);
      }
    }
    if (main) {
      try {
        results.micButtons = await main.webContents.executeJavaScript(
          "window.__ocvApi ? window.__ocvApi.count() : 0",
          true,
        );
      } catch (error) {
        results.micButtonError = String(error && error.message);
      }
      try {
        results.micButtonInfo = await main.webContents.executeJavaScript(
          `(() => Array.from(document.querySelectorAll('[data-action=ocv-voice]')).map((b) => {
            const r = b.getBoundingClientRect();
            const s = b.nextElementSibling;
            const sr = s ? s.getBoundingClientRect() : null;
            const host = b.closest('[data-component]');
            return {
              visible: !!b.offsetParent,
              rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
              host: host ? host.getAttribute('data-component') : null,
              send: s ? s.getAttribute('data-action') : null,
              sendRect: sr ? [Math.round(sr.x), Math.round(sr.y), Math.round(sr.width), Math.round(sr.height)] : null
            };
          }))()`,
          true,
        );
      } catch (error) {
        results.micButtonInfoError = String(error && error.message);
      }
      if (results.micButtons > 0) {
        try {
          results.micClick = await main.webContents.executeJavaScript(
            "(() => { const b = document.querySelector('[data-action=ocv-voice]'); if (!b) return false; b.click(); return true; })()",
            true,
          );
          await sleep(1400);
          results.micClickMode = mode;
          results.micClickState = await main.webContents.executeJavaScript(
            "window.__ocvApi ? window.__ocvApi.state() : null",
            true,
          );
          const beforeAudio = audioEventCount;
          stopListening();
          for (let i = 0; i < 40 && audioEventCount === beforeAudio; i++) await sleep(150);
          results.micAudioArrived = audioEventCount > beforeAudio;
          results.micAudioDelta = audioEventCount - beforeAudio;
          results.micStopMode = mode;
          cancelListening();
          await sleep(400);
          results.micStateAfterCancel = await main.webContents.executeJavaScript(
            "window.__ocvApi ? window.__ocvApi.state() : null",
            true,
          );
        } catch (error) {
          results.micClickError = String(error && error.message);
        }
      }
    }
  } catch (error) {
    results.fatal = String((error && error.message) || error);
  }
  log("selftest", results);
  try {
    if (overlay && !overlay.isDestroyed()) overlay.destroy();
  } catch {}
  await sleep(600);
  app.quit();
}

app.whenReady().then(() => {
  if (!app.hasSingleInstanceLock()) {
    log("secondary instance, skipping");
    return;
  }
  loadConfig();
  log("init", {
    app: app.getVersion(),
    electron: process.versions.electron,
    dataDir,
    config: { hotkey: config.hotkey, language: config.language, threads: config.threads },
    selftest: process.env.OC_VOICE_SELFTEST === "1",
  });
  registerHotkey();
  for (const win of BrowserWindow.getAllWindows()) attachMicButton(win);
  ipcMain.on(CH.ready, (event) => {
    if (!overlay || overlay.isDestroyed() || event.sender !== overlay.webContents) return;
    log("overlay ready");
    if (overlayReadyResolver) {
      overlayReadyResolver();
      overlayReadyResolver = null;
    }
    if (mode === "listening") sendToOverlay(CH.start);
  });
  ipcMain.on(CH.audio, (event, arrayBuffer, meta) => {
    if (!overlay || overlay.isDestroyed() || event.sender !== overlay.webContents) return;
    void handleAudio(arrayBuffer, meta);
  });
  ipcMain.on(CH.cancel, (event) => {
    if (!overlay || overlay.isDestroyed() || event.sender !== overlay.webContents) return;
    cancelListening();
  });
  ipcMain.on(CH.error, (event, message) => {
    if (!overlay || overlay.isDestroyed() || event.sender !== overlay.webContents) return;
    log("overlay error", message);
    finishWithState("error", String(message || "麦克风错误"), 3600);
  });
  ipcMain.on(CH.hover, (event, ignore) => {
    if (!overlay || overlay.isDestroyed() || event.sender !== overlay.webContents) return;
    try {
      overlay.setIgnoreMouseEvents(!!ignore, { forward: true });
    } catch {}
  });
  app.on("will-quit", () => {
    try {
      globalShortcut.unregisterAll();
    } catch {}
  });
  if (process.env.OC_VOICE_SELFTEST === "1") void runSelfTest();
});
