// ==oc-voice tooling== 下载语音引擎与模型(供 setup-voice-data.ps1 调用)
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";

const ENGINE_VERSION = "v1.13.8";
const ENGINE_ARCHIVE = `sherpa-onnx-${ENGINE_VERSION}-win-x64-shared-MT-Release.tar.bz2`;
const ENGINE_DIR_NAME = `sherpa-onnx-${ENGINE_VERSION}-win-x64-shared-MT-Release`;
const ENGINE_URLS = [
  `https://github.com/k2-fsa/sherpa-onnx/releases/download/${ENGINE_VERSION}/${ENGINE_ARCHIVE}`,
  `https://ghfast.top/https://github.com/k2-fsa/sherpa-onnx/releases/download/${ENGINE_VERSION}/${ENGINE_ARCHIVE}`,
];
const MODEL_FILE = "model.int8.onnx";
const MODEL_SIZE = 239239841;
const MODEL_URLS = [
  `https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/${MODEL_FILE}`,
  `https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/${MODEL_FILE}`,
];
const TOKENS_FILE = "tokens.txt";
const TOKENS_URLS = MODEL_URLS.map((u) => u.replace(MODEL_FILE, TOKENS_FILE));

const dataDir = process.argv[2];
if (!dataDir) {
  console.error("usage: fetch-assets.mjs <dataDir>");
  process.exit(2);
}

const engineRoot = path.join(dataDir, "engine");
const modelDir = path.join(dataDir, "model");
const tmpDir = path.join(dataDir, "tmp");
fs.mkdirSync(engineRoot, { recursive: true });
fs.mkdirSync(modelDir, { recursive: true });
fs.mkdirSync(tmpDir, { recursive: true });

async function download(urls, dest, options = {}) {
  const { expectedSize = 0, minSize = 0 } = options;
  const tmpDest = dest + ".part";
  for (const url of urls) {
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        console.log(`[download] ${url} (attempt ${attempt})`);
        const response = await fetch(url, { redirect: "follow" });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const total = Number(response.headers.get("content-length") || 0);
        let received = 0;
        let lastLog = 0;
        const body = Readable.fromWeb(response.body);
        body.on("data", (chunk) => {
          received += chunk.length;
          if (received - lastLog > 25 * 1024 * 1024) {
            lastLog = received;
            const pct = total ? ` (${((received / total) * 100).toFixed(0)}%)` : "";
            console.log(`[download] ${(received / 1048576).toFixed(1)} MB${pct}`);
          }
        });
        await pipeline(body, fs.createWriteStream(tmpDest));
        const size = fs.statSync(tmpDest).size;
        if (minSize && size < minSize) throw new Error(`file too small: ${size}`);
        if (expectedSize && Math.abs(size - expectedSize) > 1024 * 1024)
          throw new Error(`unexpected size: ${size} (expected ~${expectedSize})`);
        fs.renameSync(tmpDest, dest);
        console.log(`[download] done ${dest} ${(size / 1048576).toFixed(1)} MB`);
        return;
      } catch (error) {
        console.warn(`[download] failed: ${error.message}`);
        try {
          fs.rmSync(tmpDest, { force: true });
        } catch {}
        await new Promise((r) => setTimeout(r, 1500 * attempt));
      }
    }
  }
  throw new Error(`所有下载源都失败了: ${urls[0]}`);
}

function engineReady() {
  return fs.existsSync(path.join(engineRoot, ENGINE_DIR_NAME, "bin", "sherpa-onnx-offline.exe"));
}

if (engineReady()) {
  console.log("[engine] 已存在,跳过下载");
} else {
  const archivePath = path.join(engineRoot, ENGINE_ARCHIVE);
  await download(ENGINE_URLS, archivePath, { minSize: 20 * 1024 * 1024 });
  console.log("[engine] 解压中…");
  const result = spawnSync("tar", ["-xjf", archivePath, "-C", engineRoot], { stdio: "inherit" });
  if (result.status !== 0) throw new Error("tar 解压失败");
  fs.rmSync(archivePath, { force: true });
  if (!engineReady()) throw new Error("解压后未找到 sherpa-onnx-offline.exe");
  console.log("[engine] 完成");
}

const modelPath = path.join(modelDir, MODEL_FILE);
if (fs.existsSync(modelPath) && fs.statSync(modelPath).size === MODEL_SIZE) {
  console.log("[model] 已存在,跳过下载");
} else {
  await download(MODEL_URLS, modelPath, { expectedSize: MODEL_SIZE, minSize: 200 * 1024 * 1024 });
  console.log("[model] 完成");
}

const tokensPath = path.join(modelDir, TOKENS_FILE);
if (fs.existsSync(tokensPath) && fs.statSync(tokensPath).size > 1000) {
  console.log("[tokens] 已存在,跳过下载");
} else {
  await download(TOKENS_URLS, tokensPath, { minSize: 1000 });
  console.log("[tokens] 完成");
}

console.log("[done] 语音数据已就绪:", dataDir);
