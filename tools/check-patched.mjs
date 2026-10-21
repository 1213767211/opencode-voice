// ==oc-voice share tooling== 检查 app.asar 是否已打入语音模块(且是当前版本)
// 用法: node check-patched.mjs <app.asar>
// 退出码: 0 = 已打补丁且版本匹配, 1 = 未打补丁或版本过旧(需要重新打), 2 = 参数/读取错误
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

// 与 patch/out/voice/main.js 里的 OCV_PATCH_VERSION 保持一致
const EXPECTED_VERSION = 3;

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, "package.json"));

const file = process.argv[2];
if (!file) {
  console.error("usage: check-patched.mjs <app.asar>");
  process.exit(2);
}

try {
  const asar = require("@electron/asar");
  const entries = asar.listPackage(file);
  const hit = entries.some((e) => e.includes("out\\voice\\") || e.includes("out/voice/"));
  if (!hit) process.exit(1);
  // 版本校验:补丁升级后旧版本必须重打(例如修复"关窗口后点图标没反应"的那次)
  let source = "";
  try {
    source = asar.extractFile(file, path.join("out", "voice", "main.js")).toString("utf8");
  } catch {
    source = "";
  }
  const matched = source.match(/OCV_PATCH_VERSION\s*=\s*(\d+)/);
  const version = matched ? Number(matched[1]) : 0;
  process.exit(version >= EXPECTED_VERSION ? 0 : 1);
} catch (error) {
  console.error("check failed:", (error && error.message) || error);
  process.exit(2);
}
