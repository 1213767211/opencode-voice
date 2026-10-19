// ==oc-voice tooling== asar 解包/重打包辅助脚本(供 install-voice.ps1 调用)
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const modRoot = path.dirname(here);
const requireFromTools = createRequire(path.join(modRoot, ".tools", "package.json"));
const asar = requireFromTools("@electron/asar");

const [command, ...args] = process.argv.slice(2);

function usage() {
  console.error("usage: asar-tool.mjs extract|pack|list <args>");
  process.exit(2);
}

function countFiles(dir) {
  let files = 0;
  let node = 0;
  let exe = 0;
  const stack = [dir];
  while (stack.length) {
    const cur = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(cur, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const full = path.join(cur, entry.name);
      if (entry.isDirectory()) stack.push(full);
      else if (entry.isFile()) {
        files++;
        if (entry.name.endsWith(".node")) node++;
        else if (entry.name.endsWith(".exe")) exe++;
      }
    }
  }
  return { files, node, exe };
}

try {
  if (command === "extract") {
    const [archive, dest] = args;
    if (!archive || !dest) usage();
    await asar.extractAll(archive, dest);
    const unpackedSibling = archive + ".unpacked";
    if (fs.existsSync(unpackedSibling)) {
      fs.cpSync(unpackedSibling, dest, { recursive: true, force: true });
      console.log("restored unpacked files from", unpackedSibling);
    }
    const count = countFiles(dest);
    console.log("extracted", archive, "->", dest, `(${count.files} files, ${count.node} .node, ${count.exe} .exe)`);
  } else if (command === "pack") {
    const [src, dest, unpackDir] = args;
    if (!src || !dest) usage();
    await asar.createPackageWithOptions(src, dest, unpackDir ? { unpackDir } : {});
    const unpackedDir = dest + ".unpacked";
    const count = fs.existsSync(unpackedDir) ? countFiles(unpackedDir) : { files: 0, node: 0, exe: 0 };
    console.log("packed", src, "->", dest, `(unpacked: ${count.files} files, ${count.node} .node, ${count.exe} .exe)`);
  } else if (command === "list") {
    const [archive] = args;
    if (!archive) usage();
    for (const entry of asar.listPackage(archive)) console.log(entry);
  } else {
    usage();
  }
} catch (error) {
  console.error("asar-tool failed:", (error && error.stack) || error);
  process.exit(1);
}
