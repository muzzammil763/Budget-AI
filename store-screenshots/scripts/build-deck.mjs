// Builds app-store-screenshots.json for Budget AI in the Bento Keynote Grid
// style (style-prompts/15-bento-keynote-grid.md). Geometry is authored on the
// 1320px grid: 56px margins, 104px column pitch, 40px gutters, 60px radius.
// Run: node scripts/build-deck.mjs   (then reload the editor)
import fs from "node:fs";

const col = (n) => 56 + (n - 1) * 104;
const span = (k) => 64 * k + 40 * (k - 1);

const DEVICES = {
  iphone: {
    canvasW: 1320,
    canvasH: 2868,
    dir: "/screenshots/apple/iphone/en",
    // Apple bezel public/frames/iphone-portrait.png (1470×3000).
    aspect: 1470 / 3000,
    screenTop: 66 / 1470,
    screenH: (2933 - 66) / 1470,
    crown: 300,
    floor: 376,
  },
  android: {
    canvasW: 1080,
    canvasH: 1920,
    dir: "/screenshots/android/phone/en",
    // Built-in AndroidPhone frame: 9:19.5, screen at 2% top, 96% tall.
    aspect: 9 / 19.5,
    screenTop: 0.02 * (19.5 / 9),
    screenH: 0.96 * (19.5 / 9),
    crown: 260,
    floor: 300,
    // A narrower phone on the shorter 9:16 canvas, so more of the screen shows.
    phoneScale: 0.8,
  },
};

function build(deviceKey) {
  const d = DEVICES[deviceKey];
  const s = d.canvasW / 1320;
  const HU = d.canvasH / s; // canvas height in grid units
  const bottom = HU - 56;
  const report = [];

  const caption = (y, lines, fs, w = 1208) => ({
    x: 56 * s,
    y: y * s,
    width: w * s,
    height: (lines * fs * 0.98 + 24) * s,
    rotation: 0,
    zIndex: 4,
  });

  // Phone inside a stage tile; reports how much is visible and where the
  // stage edge crops the screenshot (as a fraction of its height).
  // `top` < 0 hangs the phone from the stage's top edge instead: its bottom
  // sits that far above the stage bottom and the stage top crops the screen.
  const phone = (id, stage, baseW, top, shot) => {
    const W = baseW * (d.phoneScale ?? 1);
    const x = stage.x + (stage.w - W) / 2;
    const H = W / d.aspect;
    const y = top >= 0 ? stage.y + top : stage.y + stage.h + top - H;
    const screenTop = y + d.screenTop * W;
    const visible = (Math.min(stage.y + stage.h, y + H) - Math.max(stage.y, y)) / HU;
    const crop = top >= 0
      ? `crop at ${(((stage.y + stage.h - screenTop) / (d.screenH * W)) * 100).toFixed(1)}%`
      : `shows from ${(((stage.y - screenTop) / (d.screenH * W)) * 100).toFixed(1)}% down`;
    report.push(`${deviceKey} ${id}: visible ${(visible * 100).toFixed(1)}%, ${crop} of ${shot}`);
    return { x: x * s, y: y * s, width: W * s, height: H * s, rotation: 0, zIndex: 2 };
  };

  const slide = (id, { headline, align, captionRect, shot, device, tiles, inverted, typography }) => ({
    id,
    layout: "device-bottom",
    label: { en: "" },
    headline: { en: headline },
    screenshot: shot ? `${d.dir}/${shot}.png` : "",
    captionAlign: align,
    ...(inverted ? { inverted: true, backgroundColor: "#000000" } : {}),
    typography,
    transforms: { caption: captionRect, ...(device ? { device } : {}) },
    tiles,
  });

  const fs140 = { headlineScale: 1 };
  const fs124 = { headlineScale: 124 / 140 };
  const fs142 = { headlineScale: 142 / 140 };
  const fs132 = { headlineScale: 132 / 140 };

  const crownY = 412;
  const crownH = d.crown;
  const l1StageY = crownY + crownH + 40;

  // 1 · Hero (L1 Crown + Stage)
  const s1Stage = { id: "stage", kind: "stage", x: 56, y: l1StageY, w: 1208, h: bottom - l1StageY, fill: "sky" };
  const s1 = slide("hero", {
    headline: "Talk money.\n[[It logs itself.]]",
    align: "center",
    captionRect: caption(96, 2, 140),
    typography: fs140,
    shot: "chat2_light",
    device: phone("hero", s1Stage, 1120, 80, "chat2_light"),
    tiles: [
      { id: "ways", kind: "stat", x: col(1), y: crownY, w: span(4), h: crownH, fill: "brand", eyebrow: "Type, talk or snap", value: "3", unit: "ways", valueSize: 190 },
      { id: "say", kind: "icon", x: col(5), y: crownY, w: span(4), h: crownH, fill: "white", icon: "Mic", label: "Say it.", labelSize: 60 },
      { id: "snap", kind: "icon", x: col(9), y: crownY, w: span(4), h: crownH, fill: "sage", icon: "Camera", label: "Snap it.", labelSize: 60 },
      s1Stage,
    ],
  });

  // 2 · Differentiator (L4 Split crown)
  const s2Stage = { id: "stage", kind: "stage", x: 56, y: 752, w: 1208, h: bottom - 752, fill: "tint" };
  const s2 = slide("receipts", {
    headline: "Snap a\nreceipt.\n[[It's logged.]]",
    align: "left",
    captionRect: caption(96, 3, 124, 688),
    typography: fs124,
    shot: "receipt_light",
    device: phone("receipts", s2Stage, 1110, 80, "receipt_light"),
    tiles: [
      { id: "lines", kind: "inline", x: col(1), y: 528, w: span(7), h: 184, fill: "white", icon: "ReceiptText", label: "Every line, read." },
      { id: "photos", kind: "stat", x: col(8), y: 96, w: span(5), h: 616, fill: "brand", eyebrow: "Per message", value: "3", unit: "photos", valueSize: 240, caption: "Receipts, bills or screenshots." },
      s2Stage,
    ],
  });

  // 3 · Feature (L2 Stage + Floor)
  const floorY = bottom - d.floor;
  const s3Stage = { id: "stage", kind: "stage", x: 56, y: 272, w: 1208, h: floorY - 40 - 272, fill: "night" };
  const s3 = slide("voice", {
    headline: "Just [[say it.]]",
    align: "left",
    captionRect: caption(94, 1, 142),
    typography: fs142,
    shot: "voice_light",
    device: phone("voice", s3Stage, 1060, 56, "voice_light"),
    tiles: [
      s3Stage,
      { id: "two", kind: "stat", x: col(1), y: floorY, w: span(4), h: d.floor, fill: "brand", eyebrow: "From one sentence", value: "2", unit: "entries", valueSize: 196 },
      { id: "hold", kind: "icon", x: col(5), y: floorY, w: span(4), h: d.floor, fill: "white", icon: "Mic", label: "Hold to\ntalk.", labelSize: 60 },
      { id: "currency", kind: "icon", x: col(9), y: floorY, w: span(4), h: d.floor, fill: "sky", icon: "Coins", label: "Any\ncurrency.", labelSize: 60 },
    ],
  });

  // 4 · Feature (L1 Crown + Stage)
  const s4Stage = { id: "stage", kind: "stage", x: 56, y: l1StageY, w: 1208, h: bottom - l1StageY, fill: "tint" };
  const s4 = slide("finances", {
    headline: "Every dollar.\n[[In one place.]]",
    align: "center",
    captionRect: caption(96, 2, 140),
    typography: fs140,
    shot: "finances_light",
    device: phone("finances", s4Stage, 1120, 80, "finances_light"),
    tiles: [
      { id: "entries", kind: "stat", x: col(1), y: crownY, w: span(4), h: crownH, fill: "brand", eyebrow: "Expenses this month", value: "23", valueSize: 190 },
      { id: "income", kind: "icon", x: col(5), y: crownY, w: span(4), h: crownH, fill: "white", icon: "ArrowDownLeft", iconColor: "#1F7A4D", label: "Income too.", labelSize: 56 },
      { id: "search", kind: "icon", x: col(9), y: crownY, w: span(4), h: crownH, fill: "sage", icon: "Search", label: "Find any.", labelSize: 56 },
      s4Stage,
    ],
  });

  // 5 · Feature (L1b Widget crown + Stage)
  const l1bCrownH = deviceKey === "iphone" ? 376 : 300;
  const l1bStageY = 272 + l1bCrownH + 40;
  const s5Stage = { id: "stage", kind: "stage", x: 56, y: l1bStageY, w: 1208, h: bottom - l1bStageY, fill: "sky" };
  const s5 = slide("insights", {
    headline: "Spot the [[leaks.]]",
    align: "left",
    captionRect: caption(94, 1, 142),
    typography: fs142,
    shot: "insights_chart_light",
    device: phone("insights", s5Stage, 1080, 56, "insights_chart_light"),
    tiles: [
      { id: "peak", kind: "stat", x: col(1), y: 272, w: span(8), h: l1bCrownH, fill: "brand", eyebrow: "Peak day, 13 October", value: "$146", valueSize: 220 },
      { id: "compare", kind: "widget", x: col(9), y: 272, w: span(4), h: l1bCrownH, fill: "widgetNight", src: "/widgets/w-compare.png", fit: "cover" },
      s5Stage,
    ],
  });

  // 6 · Inverted (L1 Crown + Stage, dark)
  const s6Stage = { id: "stage", kind: "stage", x: 56, y: l1StageY, w: 1208, h: bottom - l1StageY, fill: "white" };
  const s6 = slide("summary", {
    headline: "Your month.\n[[Summed up.]]",
    align: "center",
    captionRect: caption(96, 2, 140),
    typography: fs140,
    inverted: true,
    shot: "summary_light",
    device: phone("summary", s6Stage, 1120, -80, "summary_light"),
    tiles: [
      { id: "bills", kind: "stat", x: col(1), y: crownY, w: span(4), h: crownH, fill: "brand", eyebrow: "Bills, top category", value: "30", unit: "%", valueSize: 190 },
      { id: "tap", kind: "icon", x: col(5), y: crownY, w: span(4), h: crownH, fill: "white", icon: "Sparkles", label: "One tap.", labelSize: 60 },
      { id: "monthly", kind: "icon", x: col(9), y: crownY, w: span(4), h: crownH, fill: "tint", icon: "CalendarDays", label: "Every\nmonth.", labelSize: 56 },
      s6Stage,
    ],
  });

  // 7 · Ecosystem (L1b Widget crown + Stage)
  const s7Stage = { id: "stage", kind: "stage", x: 56, y: l1bStageY, w: 1208, h: bottom - l1bStageY, fill: "sky" };
  const s7 = slide("widgets", {
    headline: "Glance. [[Done.]]",
    align: "left",
    captionRect: caption(94, 1, 142),
    typography: fs142,
    shot: "widgets_home",
    device: phone("widgets", s7Stage, 1080, 56, "widgets_home"),
    tiles: [
      { id: "summary-widget", kind: "widget", x: col(1), y: 272, w: span(8), h: l1bCrownH, fill: "white", src: "/widgets/w-summary.png", fit: "cover" },
      { id: "count", kind: "stat", x: col(9), y: 272, w: span(4), h: l1bCrownH, fill: "brand", eyebrow: "Home Screen widgets", value: "8", valueSize: 220 },
      s7Stage,
    ],
  });

  // 8 · Closer (L3 Mosaic, no phone)
  const rows = deviceKey === "iphone"
    ? [[400, 640], [1080, 376], [1496, 640], [2176, 636]]
    : [[400, 480], [920, 330], [1290, 480], [1810, bottom - 1810]];
  const [A, B, C, D] = rows;
  const s8 = slide("closer", {
    headline: "Your money.\n[[One chat away.]]",
    align: "center",
    captionRect: caption(96, 2, 132),
    typography: fs132,
    tiles: [
      { id: "currencies", kind: "stat", x: col(1), y: A[0], w: span(7), h: A[1], fill: "brand", eyebrow: "Currencies built in", value: "16", valueSize: 250, caption: "Plus any symbol you add." },
      { id: "talk", kind: "icon", x: col(8), y: A[0], w: span(5), h: A[1], fill: "sage", icon: "Mic", label: "Talk or\ntype.", labelSize: 76 },
      { id: "recent", kind: "widget", x: col(1), y: B[0], w: span(8), h: B[1], fill: "white", src: "/widgets/w-recent.png", fit: "cover" },
      { id: "expenses", kind: "widget", x: col(9), y: B[0], w: span(4), h: B[1], fill: "white", src: "/widgets/w-expenses.png", fit: "cover" },
      { id: "receipts", kind: "icon", x: col(1), y: C[0], w: span(5), h: C[1], fill: "sky", icon: "ScanLine", label: "Snap\nreceipts.", labelSize: 76 },
      { id: "ask", kind: "list", x: col(6), y: C[0], w: span(7), h: C[1], fill: "white", eyebrow: "Just ask it to", items: ["Log it.", "Fix it.", "Sum it up."], labelSize: 62 },
      { id: "identity", kind: "identity", x: col(1), y: D[0], w: span(4), h: D[1], fill: "white", src: "/app-icon.png", label: "Budget AI", labelSize: 56, caption: "Money, by chat." },
      { id: "lock", kind: "image", x: col(5), y: D[0], w: span(8), h: D[1], fill: "night", src: "/widgets/lock.png", fit: "cover" },
    ],
  });

  return { slides: [s1, s2, s3, s4, s5, s6, s7, s8], report };
}

const iphone = build("iphone");
const android = build("android");
const feature = {
  id: "feature",
  layout: "feature-graphic",
  label: { en: "" },
  headline: { en: "Talk money. It logs itself." },
  screenshot: "",
};

const state = {
  schemaVersion: 3,
  appName: "Budget AI",
  themeId: "bento-keynote-grid",
  connectedCanvas: false,
  locales: ["en"],
  locale: "en",
  device: "iphone",
  orientation: "portrait",
  appIcon: "/app-icon.png",
  scene: {
    backdrop: "solid",
    span: false,
    decoration: "none",
    shadow: 40,
    glow: 0,
    tilt: 0,
    headlineWeight: 700,
    headlineScale: 1,
    headlineCase: "as-typed",
    captionAlign: "auto",
  },
  slidesByDevice: {
    iphone: iphone.slides,
    android: android.slides,
    "feature-graphic": [feature],
  },
};

fs.writeFileSync("app-store-screenshots.json", JSON.stringify(state, null, 2) + "\n");
console.log([...iphone.report, ...android.report].join("\n"));
