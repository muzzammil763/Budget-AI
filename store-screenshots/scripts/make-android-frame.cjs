// Draws public/frames/android-portrait.png: an original premium Android phone
// bezel (graphite metal rail, thin black border, centred punch-hole camera)
// with a transparent screen cut to the 9:20 shape of the Android captures.
// Run: node scripts/make-android-frame.cjs
const sharp = require("sharp");

const screenW = 1080;
const screenH = 2400; // 720×1600 captures are 9:20
const border = 30; // black glass border
const rail = 16; // metal frame
const button = 7; // side keys protrude this far
const inset = border + rail;
const bodyW = screenW + 2 * inset;
const bodyH = screenH + 2 * inset;
const W = bodyW + 2 * button;
const H = bodyH;
const bodyX = button;
const screenR = 104;
const glassR = screenR + border;
const bodyR = glassR + rail;
const cam = { x: bodyX + bodyW / 2, y: inset + 44, r: 19 };

const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">
  <defs>
    <linearGradient id="metal" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#8E8E93"/>
      <stop offset="0.18" stop-color="#3A3A3D"/>
      <stop offset="0.5" stop-color="#5B5B60"/>
      <stop offset="0.82" stop-color="#2B2B2E"/>
      <stop offset="1" stop-color="#7C7C82"/>
    </linearGradient>
    <linearGradient id="key" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#2A2A2D"/>
      <stop offset="1" stop-color="#6E6E73"/>
    </linearGradient>
    <radialGradient id="lens" cx="0.38" cy="0.35" r="0.7">
      <stop offset="0" stop-color="#2B3550"/>
      <stop offset="0.45" stop-color="#0B0D14"/>
      <stop offset="1" stop-color="#000000"/>
    </radialGradient>
    <mask id="screen">
      <rect width="${W}" height="${H}" fill="#fff"/>
      <rect x="${bodyX + inset}" y="${inset}" width="${screenW}" height="${screenH}" rx="${screenR}" fill="#000"/>
      <circle cx="${cam.x}" cy="${cam.y}" r="${cam.r + 4}" fill="#fff"/>
    </mask>
  </defs>
  <!-- side keys: power and volume on the right -->
  <rect x="${bodyX + bodyW - 4}" y="${H * 0.25}" width="${button + 4}" height="${H * 0.075}" rx="4" fill="url(#key)"/>
  <rect x="${bodyX + bodyW - 4}" y="${H * 0.345}" width="${button + 4}" height="${H * 0.13}" rx="4" fill="url(#key)"/>
  <g mask="url(#screen)">
    <rect x="${bodyX}" y="0" width="${bodyW}" height="${bodyH}" rx="${bodyR}" fill="url(#metal)"/>
    <rect x="${bodyX + 2.5}" y="2.5" width="${bodyW - 5}" height="${bodyH - 5}" rx="${bodyR - 2.5}" fill="none" stroke="rgba(255,255,255,.35)" stroke-width="2"/>
    <rect x="${bodyX + rail}" y="${rail}" width="${bodyW - 2 * rail}" height="${bodyH - 2 * rail}" rx="${glassR}" fill="#050506"/>
    <rect x="${bodyX + rail + 1.5}" y="${rail + 1.5}" width="${bodyW - 2 * rail - 3}" height="${bodyH - 2 * rail - 3}" rx="${glassR - 1.5}" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="2"/>
    <circle cx="${cam.x}" cy="${cam.y}" r="${cam.r + 4}" fill="#000"/>
    <circle cx="${cam.x}" cy="${cam.y}" r="${cam.r}" fill="url(#lens)"/>
    <circle cx="${cam.x}" cy="${cam.y}" r="${cam.r - 1}" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="1.5"/>
    <circle cx="${cam.x - 6}" cy="${cam.y - 6}" r="4" fill="rgba(160,190,255,.35)"/>
  </g>
</svg>`;

sharp(Buffer.from(svg))
  .png()
  .toFile("public/frames/android-portrait.png")
  .then((info) => console.log(`android-portrait.png ${info.width}×${info.height}`));
