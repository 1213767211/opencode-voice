// ==oc-voice share tooling== 检查 app.asar 是否已打入语音模块
// 用法: node check-patched.mjs <app.asar>
// 退出码: 0 = 已打补丁, 1 = 未打补丁, 2 = 参数/读取错误
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

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
  process.exit(hit ? 0 : 1);
} catch (error) {
  console.error("check failed:", (error && error.message) || error);
  process.exit(2);
}
