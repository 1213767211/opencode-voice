// ==oc-voice-appended==
import("../voice/main.js").catch(async (error) => {
  try {
    const fs = await import("node:fs");
    const path = await import("node:path");
    const dir = path.join(path.dirname(path.dirname(process.execPath)), "voice-data", "logs");
    fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(path.join(dir, "load-error.log"), new Date().toISOString() + " " + String((error && error.stack) || error) + "\r\n");
  } catch {}
  console.error("[oc-voice] failed to load", error);
});
