// Exports one device deck through the editor's own "Export bundle" button.
// Usage: node scripts/export.cjs <device> <outDir>   (dev server on :3000)
const fs = require("node:fs/promises");
const path = require("node:path");
const JSZip = require("jszip");
const { chromium } = require("playwright");

(async () => {
  const [device = "iphone", outDir = "exports"] = process.argv.slice(2);
  const project = JSON.parse(await fs.readFile("app-store-screenshots.json", "utf8"));
  project.device = device;
  await fs.writeFile("app-store-screenshots.json", JSON.stringify(project, null, 2) + "\n");

  const browser = await chromium.launch({ channel: "chrome", headless: true });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  await page.goto("http://localhost:3000", { waitUntil: "networkidle" });
  await page.getByRole("button", { name: "Export bundle", exact: true }).waitFor();
  await page.evaluate(() => document.fonts.ready);
  const downloaded = page.waitForEvent("download", { timeout: 300000 });
  await page.getByRole("button", { name: "Export bundle", exact: true }).click();
  const file = await (await downloaded).path();
  const zip = await JSZip.loadAsync(await fs.readFile(file));
  const written = [];
  for (const [name, entry] of Object.entries(zip.files)) {
    if (entry.dir) continue;
    const target = path.join(outDir, name);
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, await entry.async("nodebuffer"));
    written.push(name);
  }
  console.log(written.join("\n"));
  await browser.close();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
