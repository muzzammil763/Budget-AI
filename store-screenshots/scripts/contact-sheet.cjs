// Lays exported PNGs side by side for review: node scripts/contact-sheet.cjs <dir> <out.png> [height]
const fs = require("node:fs");
const path = require("node:path");
const sharp = require("sharp");
(async () => {
  const [dir, out, h = "1100"] = process.argv.slice(2);
  const height = Number(h);
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".png")).sort();
  const parts = await Promise.all(files.map(async (f) => {
    const input = await sharp(path.join(dir, f)).resize({ height }).png().toBuffer();
    return { input, width: (await sharp(input).metadata()).width };
  }));
  let left = 0;
  const composite = parts.map((p) => { const c = { input: p.input, left, top: 0 }; left += p.width + 24; return c; });
  await sharp({ create: { width: left, height, channels: 3, background: "#9a9a9a" } }).composite(composite).png().toFile(out);
})();
