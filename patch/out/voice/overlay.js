// ==oc-voice== 录音浮层:负责采集麦克风、实时电平动画、编码 WAV 并回传主进程
const { ipcRenderer } = require("electron");

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

const SAMPLE_RATE = 16000;

const elPill = document.getElementById("pill");
const elMic = document.getElementById("mic");
const elStatus = document.getElementById("status");
const elHint = document.getElementById("hint");
const elSpinner = document.getElementById("spinner");
const elClose = document.getElementById("close");
const elBars = Array.from(document.querySelectorAll("#bars i"));

let state = "idle";
let stopRequested = false;
let lastVoiceAt = 0;

let stream = null;
let audioCtx = null;
let sourceNode = null;
let processorNode = null;
let muteGain = null;
let buffers = [];
let totalSamples = 0;
let sumSquares = 0;

let level = 0;
let displayLevel = 0;
let rafId = null;

function teardownAudio() {
  try {
    if (processorNode) processorNode.onaudioprocess = null;
  } catch {}
  try {
    if (processorNode) processorNode.disconnect();
  } catch {}
  try {
    if (sourceNode) sourceNode.disconnect();
  } catch {}
  try {
    if (muteGain) muteGain.disconnect();
  } catch {}
  try {
    if (stream) stream.getTracks().forEach((track) => track.stop());
  } catch {}
  try {
    if (audioCtx && audioCtx.state !== "closed") void audioCtx.close();
  } catch {}
  stream = null;
  audioCtx = null;
  sourceNode = null;
  processorNode = null;
  muteGain = null;
}

function animateBars() {
  displayLevel += (level - displayLevel) * 0.25;
  const base = Math.max(0.06, Math.min(1, displayLevel * 9));
  const phases = [0, 1.1, 2.2, 3.3, 2.2, 1.1, 0];
  for (let i = 0; i < elBars.length; i++) {
    const wave = 0.55 + 0.45 * Math.sin(Date.now() / 130 + phases[i]);
    const h = 5 + base * wave * 20;
    elBars[i].style.height = h.toFixed(1) + "px";
  }
  rafId = requestAnimationFrame(animateBars);
}

function stopBars() {
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
  for (const bar of elBars) bar.style.height = "5px";
}

function setVisual(mode, message) {
  elPill.className = "mode-" + mode;
  elMic.className = mode;
  elSpinner.style.display = mode === "transcribing" ? "block" : "none";
  if (mode === "listening") {
    elStatus.textContent = "正在聆听…";
    elHint.textContent = message || "说完停顿片刻自动识别,再点麦克风可结束";
    elClose.style.display = "flex";
  } else if (mode === "transcribing") {
    elStatus.textContent = "识别中…";
    elHint.textContent = "正在把语音转成文字";
    elClose.style.display = "none";
  } else if (mode === "done") {
    elStatus.textContent = message || "已输入";
    elHint.textContent = "文字已插入输入框";
    elClose.style.display = "none";
  } else if (mode === "error") {
    elStatus.textContent = message || "出错了";
    elHint.textContent = "再按一次快捷键重试";
    elClose.style.display = "flex";
  } else {
    elStatus.textContent = message || "";
    elHint.textContent = "";
  }
}

function encodeWav(samples, sampleRate) {
  const length = samples.length;
  const buffer = new ArrayBuffer(44 + length * 2);
  const view = new DataView(buffer);
  const writeString = (offset, value) => {
    for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i));
  };
  writeString(0, "RIFF");
  view.setUint32(4, 36 + length * 2, true);
  writeString(8, "WAVE");
  writeString(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeString(36, "data");
  view.setUint32(40, length * 2, true);
  let offset = 44;
  for (let i = 0; i < length; i++) {
    const sample = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(offset, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
    offset += 2;
  }
  return buffer;
}

function finalizeAndSend() {
  if (state !== "listening") return;
  state = "transcribing";
  stopBars();
  setVisual("transcribing");
  teardownAudio();
  const merged = new Float32Array(totalSamples);
  let offset = 0;
  for (const chunk of buffers) {
    merged.set(chunk, offset);
    offset += chunk.length;
  }
  buffers = [];
  const duration = merged.length / SAMPLE_RATE;
  const rms = merged.length ? Math.sqrt(sumSquares / merged.length) : 0;
  const wav = encodeWav(merged, SAMPLE_RATE);
  ipcRenderer.send(CH.audio, wav, { duration, rms });
}

function cancelEverything(silent) {
  teardownAudio();
  buffers = [];
  totalSamples = 0;
  sumSquares = 0;
  lastVoiceAt = 0;
  stopBars();
  if (!silent) ipcRenderer.send(CH.cancel);
}

async function startRecording() {
  if (state === "listening") return;
  if (state === "transcribing" && stopRequested) return;
  cancelEverything(true);
  state = "listening";
  stopRequested = false;
  lastVoiceAt = 0;
  setVisual("listening");
  if (rafId === null) rafId = requestAnimationFrame(animateBars);
  let media;
  try {
    media = await navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    });
  } catch (error) {
    state = "idle";
    ipcRenderer.send(CH.error, "无法访问麦克风: " + (error && error.message ? error.message : error));
    return;
  }
  if (state !== "listening") {
    try {
      media.getTracks().forEach((track) => track.stop());
    } catch {}
    return;
  }
  stream = media;
  try {
    audioCtx = new AudioContext({ sampleRate: SAMPLE_RATE });
    sourceNode = audioCtx.createMediaStreamSource(stream);
    processorNode = audioCtx.createScriptProcessor(4096, 1, 1);
    muteGain = audioCtx.createGain();
    muteGain.gain.value = 0;
    processorNode.onaudioprocess = (event) => {
      if (state !== "listening") return;
      const channel = event.inputBuffer.getChannelData(0);
      const copy = new Float32Array(channel.length);
      copy.set(channel);
      buffers.push(copy);
      totalSamples += copy.length;
      let sum = 0;
      for (let i = 0; i < copy.length; i++) sum += copy[i] * copy[i];
      sumSquares += sum;
      const rms = Math.sqrt(sum / copy.length);
      level = Math.max(rms, level * 0.86);
      const now = Date.now();
      if (rms > 0.014) lastVoiceAt = now;
      if (lastVoiceAt > 0 && now - lastVoiceAt > 1600 && totalSamples >= SAMPLE_RATE * 1.2) {
        finalizeAndSend();
      }
    };
    sourceNode.connect(processorNode);
    processorNode.connect(muteGain);
    muteGain.connect(audioCtx.destination);
  } catch (error) {
    teardownAudio();
    state = "idle";
    ipcRenderer.send(CH.error, "录音初始化失败: " + (error && error.message ? error.message : error));
  }
}

ipcRenderer.on(CH.start, () => {
  void startRecording();
});

ipcRenderer.on(CH.stop, () => {
  stopRequested = true;
  finalizeAndSend();
});

ipcRenderer.on(CH.state, (_event, payload) => {
  const next = (payload && payload.state) || "idle";
  const message = (payload && payload.message) || "";
  if (next === "cancelled") {
    state = "idle";
    stopRequested = false;
    cancelEverything(true);
    return;
  }
  if (next === "listening") {
    if (state === "listening") setVisual("listening", message);
    return;
  }
  state = next === "transcribing" ? "transcribing" : "idle";
  stopBars();
  setVisual(next, message);
});

elPill.addEventListener("click", (event) => {
  if (event.target === elClose) return;
  if (state === "listening") {
    finalizeAndSend();
  }
});

elClose.addEventListener("click", (event) => {
  event.stopPropagation();
  state = "idle";
  cancelEverything(false);
});

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    event.preventDefault();
    state = "idle";
    stopRequested = true;
    cancelEverything(false);
  }
});

let ignoringMouse = true;

window.addEventListener("mousemove", (event) => {
  const rect = elPill.getBoundingClientRect();
  const inside =
    event.clientX >= rect.left &&
    event.clientX <= rect.right &&
    event.clientY >= rect.top &&
    event.clientY <= rect.bottom;
  const nextIgnore = !inside;
  if (nextIgnore !== ignoringMouse) {
    ignoringMouse = nextIgnore;
    ipcRenderer.send(CH.hover, nextIgnore);
  }
});

setVisual("idle");
ipcRenderer.send(CH.ready);
