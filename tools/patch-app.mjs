// ==oc-voice share tooling== 把语音补丁打进 app.asar(跨平台,Windows/macOS/Linux 通用)
// 用法:
//   node patch-app.mjs --app-asar <resources/app.asar> --patch <patchRoot> [--refresh-backup] [--disable-updater] [--app-id <id>] [--quiet]
// patchRoot 目录需包含: out/voice/*.js 与 append-content.js
import { createRequire } from "node:module";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
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

async function main() {
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

    const newAsar = appAsar + ".new";
    say("packing...");
    fs.rmSync(newAsar, { force: true });
    fs.rmSync(newAsar + ".unpacked", { recursive: true, force: true });
    await asar.createPackageWithOptions(work, newAsar, { unpackDir: "node_modules/**" });
    if (!fs.existsSync(newAsar)) fail("pack output missing");
    if (!fs.existsSync(newAsar + ".unpacked")) fail("pack output unpacked missing");

    const oldUnpacked = unpacked + ".old-voice";
    fs.rmSync(oldUnpacked, { recursive: true, force: true });

    const removePath = (p) => {
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
    };

    const retry = (fn, label) => {
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
    };

    const oldAsar = appAsar + ".old-voice";
    removePath(oldAsar);
    let newAsarInPlace = false;
    let unpackedMovedAside = false;
    let newUnpackedInPlace = false;
    try {
      if (fs.existsSync(unpacked)) {
        retry(() => fs.renameSync(unpacked, oldUnpacked), "move old unpacked aside");
        unpackedMovedAside = true;
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
    try {
      removePath(oldAsar);
    } catch {}
    try {
      fs.rmSync(oldUnpacked, { recursive: true, force: true });
    } catch {}
    try {
      fs.rmSync(newAsar, { force: true });
    } catch {}
    try {
      fs.rmSync(newAsar + ".unpacked", { recursive: true, force: true });
    } catch {}

    const entries = asar.listPackage(appAsar);
    const voiceCount = entries.filter((e) => e.includes("voice")).length;
    if (voiceCount === 0) fail("verification failed: voice module not found in packed asar");
    say("done. voice entries:", voiceCount);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

main().catch((error) => {
  fail((error && error.stack) || String(error));
});
