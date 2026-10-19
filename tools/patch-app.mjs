// ==oc-voice share tooling== 把语音补丁打进 app.asar(跨平台,Windows/macOS/Linux 通用)
// 用法:
//   node patch-app.mjs --app-asar <resources/app.asar> --patch <patchRoot> [--refresh-backup] [--disable-updater] [--app-id <id>] [--quiet]
// patchRoot 目录需包含: out/voice/*.js 与 append-content.js
//
// 架构说明:在 Electron-as-node(用应用自身二进制当 node)下,asar 感知的 fs 会在解包时
// 缓存 app.asar 的打开句柄,导致同进程改名 EBUSY。因此拆成两阶段:
//   阶段一(子进程 --prepare): 解包 / 注入 / 打包出 app.asar.new, 然后退出(句柄随之释放)
//   阶段二(父进程): 只做文件交换 / 回滚 / 校验,从不读取 asar 内容
import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

// 关键:在 Electron(应用自身二进制作为 node 运行)下,asar 感知的 fs 会对任何
// 含 ".asar" 的路径打开并缓存归档句柄,导致对 app.asar 的改名/删除永远 EBUSY。
// 关闭 asar 支持后所有 fs 调用退化为普通文件操作(普通 node 下此赋值无副作用)。
process.noAsar = true;

const require = createRequire(path.join(here, "package.json"));
const asar = require("@electron/asar");

const args = process.argv.slice(2);
function opt(name) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : null;
}
const appAsar = opt("--app-asar");
const patchRoot = opt("--patch");
const refreshBackup = args.includes("--refresh-backup");
const disableUpdater = args.includes("--disable-updater");
const testAppId = opt("--app-id");
const quiet = args.includes("--quiet");
const isPrepare = args.includes("--prepare");

function say(...parts) {
  if (!quiet) console.log("[patch]", ...parts);
}
function fail(message) {
  console.error("[patch] error:", message);
  process.exit(1);
}

if (!appAsar || !patchRoot) {
  fail("usage: patch-app.mjs --app-asar <app.asar> --patch <patchRoot> [--refresh-backup] [--disable-updater] [--app-id <id>] [--quiet]");
}
if (!fs.existsSync(appAsar)) fail("app.asar not found: " + appAsar);
const resources = path.dirname(appAsar);
const unpacked = path.join(resources, "app.asar.unpacked");
const backup = appAsar + ".bak-voice";
const newAsar = appAsar + ".new";

function removePath(p) {
  let st;
  try {
    st = fs.lstatSync(p);
  } catch {
    return;
  }
  if (st.isDirectory()) {
    fs.rmSync(p, { recursive: true, force: true });
  } else {
    fs.unlinkSync(p);
  }
}

function retry(fn, label) {
  let last;
  for (let i = 1; i <= 60; i++) {
    try {
      fn();
      return;
    } catch (error) {
      last = error;
      say(label, "attempt", i, "failed:", error && error.message);
      const until = Date.now() + Math.min(5000, 300 * i);
      while (Date.now() < until);
    }
  }
  throw last;
}

async function prepare() {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "ocv-"));
  try {
    say("extracting asar...");
    await asar.extractAll(appAsar, work);
    if (fs.existsSync(unpacked)) {
      fs.cpSync(unpacked, work, { recursive: true, force: true });
      say("merged app.asar.unpacked");
    }

    const indexPath = path.join(work, "out", "main", "index.js");
    if (!fs.existsSync(indexPath)) fail("out/main/index.js not found inside asar");
    let content = fs.readFileSync(indexPath, "utf8");

    const voiceSrc = path.join(patchRoot, "out", "voice");
    if (!fs.existsSync(voiceSrc)) fail("patch files not found: " + voiceSrc);
    const voiceDst = path.join(work, "out", "voice");
    fs.mkdirSync(voiceDst, { recursive: true });
    fs.cpSync(voiceSrc, voiceDst, { recursive: true, force: true });
    say("copied voice module files");

    const appendSnippetPath = path.join(patchRoot, "append-content.js");
    if (!fs.existsSync(appendSnippetPath)) fail("append-content.js not found: " + appendSnippetPath);
    const marker = "// ==oc-voice-appended==";
    const appendIndex = content.indexOf(marker);
    if (appendIndex >= 0) {
      content = content.substring(0, appendIndex).replace(/\s+$/, "") + "\r\n";
      say("removed previous injection");
    }
    const snippet = fs.readFileSync(appendSnippetPath, "utf8");
    content += "\r\n" + snippet.replace(/\s+$/, "") + "\r\n";
    say("injected voice module entry");

    if (disableUpdater) {
      const updaterOriginal = 'const UPDATER_ENABLED = app.isPackaged && CHANNEL !== "dev";';
      if (content.includes(updaterOriginal)) {
        content = content.replace(
          updaterOriginal,
          'const UPDATER_ENABLED = false; // ==oc-voice: auto update disabled to keep patch',
        );
        say("disabled auto updater");
      }
    }

    if (testAppId) {
      content = content.replace('prod: "ai.opencode.desktop"', 'prod: "' + testAppId + '"');
      say("test app id:", testAppId);
    }

    fs.writeFileSync(indexPath, content, "utf8");

    if (!fs.existsSync(backup) || refreshBackup) {
      say(refreshBackup ? "refreshing backup..." : "creating backup...");
      fs.copyFileSync(appAsar, backup);
    }

    say("packing...");
    fs.rmSync(newAsar, { force: true });
    fs.rmSync(newAsar + ".unpacked", { recursive: true, force: true });
    await asar.createPackageWithOptions(work, newAsar, { unpackDir: "node_modules/**" });
    if (!fs.existsSync(newAsar)) fail("pack output missing");
    if (!fs.existsSync(newAsar + ".unpacked")) fail("pack output unpacked missing");
    say("prepare done");
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

async function swapAndVerify() {
  const oldUnpacked = unpacked + ".old-voice";
  const oldAsar = appAsar + ".old-voice";
  removePath(oldUnpacked);
  removePath(oldAsar);

  let newAsarInPlace = false;
  let newUnpackedInPlace = false;
  try {
    if (fs.existsSync(unpacked)) {
      retry(() => fs.renameSync(unpacked, oldUnpacked), "move old unpacked aside");
    }
    retry(() => fs.renameSync(appAsar, oldAsar), "move old asar aside");
    retry(() => fs.renameSync(newAsar, appAsar), "move new asar");
    newAsarInPlace = true;
    retry(() => fs.renameSync(newAsar + ".unpacked", unpacked), "move new unpacked");
    newUnpackedInPlace = true;
  } catch (error) {
    say("swap failed, rolling back...");
    const safeRestore = (from, to) => {
      try {
        if (from && fs.existsSync(from) && !fs.existsSync(to)) fs.renameSync(from, to);
      } catch {}
    };
    try {
      if (newAsarInPlace && !newUnpackedInPlace && fs.existsSync(appAsar)) {
        fs.renameSync(appAsar, newAsar);
        newAsarInPlace = false;
      }
    } catch {}
    if (!newAsarInPlace) safeRestore(oldAsar, appAsar);
    if (!newUnpackedInPlace) safeRestore(oldUnpacked, unpacked);
    throw error;
  }

  try { removePath(oldAsar); } catch {}
  try { fs.rmSync(oldUnpacked, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(newAsar, { force: true }); } catch {}
  try { fs.rmSync(newAsar + ".unpacked", { recursive: true, force: true }); } catch {}

  const entries = asar.listPackage(appAsar);
  const voiceCount = entries.filter((e) => e.includes("voice")).length;
  if (voiceCount === 0) fail("verification failed: voice module not found in packed asar");
  say("done. voice entries:", voiceCount);
}

async function main() {
  if (isPrepare) {
    await prepare();
    return;
  }
  say("preparing patch payload (child process)...");
  const self = fileURLToPath(import.meta.url);
  const childArgs = [...args.filter((a) => a !== "--prepare"), "--prepare"];
  const result = spawnSync(process.execPath, [self, ...childArgs], {
    stdio: "inherit",
    env: process.env,
  });
  if (result.error) fail("prepare spawn failed: " + result.error.message);
  if (result.status !== 0) fail("prepare step failed (exit " + result.status + ")");
  await swapAndVerify();
}

main().catch((error) => {
  fail((error && error.stack) || String(error));
});
