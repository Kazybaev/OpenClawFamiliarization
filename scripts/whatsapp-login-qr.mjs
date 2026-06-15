import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const loginApiPath = join(
  process.env.HOME,
  ".openclaw/extensions/whatsapp/dist/login-qr-api.js",
);
const { startWebLoginWithQr, waitForWebLogin } = await import(
  pathToFileURL(loginApiPath)
);

const outputPath = new URL("../whatsapp-qr.png", import.meta.url);

const result = await startWebLoginWithQr({
  accountId: "default",
  timeoutMs: 30000,
  force: true,
});

if (!result.qrDataUrl) {
  console.log(result.message);
  process.exit(result.connected ? 0 : 1);
}

const base64 = result.qrDataUrl.replace(/^data:image\/png;base64,/, "");
writeFileSync(outputPath, Buffer.from(base64, "base64"));
console.log(`QR saved: ${outputPath.pathname}`);
console.log("Open WhatsApp -> Linked Devices -> Link a device, then scan whatsapp-qr.png");

const waitResult = await waitForWebLogin({
  accountId: "default",
  timeoutMs: 180000,
  currentQrDataUrl: result.qrDataUrl,
});

console.log(waitResult.message);
process.exit(waitResult.connected ? 0 : 1);
