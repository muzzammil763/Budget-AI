"use client";
import * as React from "react";
import * as Icons from "lucide-react";
import { img } from "@/lib/image-cache";
import type { BentoTile, BentoTileFill, Slide } from "@/lib/types";

// Bento Keynote Grid tiles (style-prompts/15-bento-keynote-grid.md).
// Tile geometry is authored on the 1320px-wide grid and scaled to the canvas,
// so the same numbers work for every export size.

export const BENTO_THEME_ID = "bento-keynote-grid";
export const BENTO_FONT = "var(--font-display), 'Inter Tight', Inter, sans-serif";
const TEXT_FONT = "var(--font-text), Inter, sans-serif";
const BASE_W = 1320;
const RADIUS = 60;
const PAD = 48;

type Palette = {
  ground: string;
  ink: string;
  ink2: string;
  fills: Record<BentoTileFill, string>;
  onFill: Partial<Record<BentoTileFill, { ink: string; eyebrow: string }>>;
  shadow: string;
  well: string;
};

const LIGHT: Palette = {
  ground: "#F5F5F7",
  ink: "#1D1D1F",
  ink2: "#5E5E63",
  fills: {
    white: "#FFFFFF",
    tint: "#F6EBE1",
    sage: "#E6F0E6",
    sky: "#E5EDF7",
    brand: "#1F57C3",
    night: "#1D1D1F",
    widget: "#FFFFFF",
    widgetNight: "#000000",
  },
  onFill: {
    brand: { ink: "#FFFFFF", eyebrow: "#E8F0FF" },
    night: { ink: "#F5F5F7", eyebrow: "#A1A1A6" },
    widgetNight: { ink: "#F5F5F7", eyebrow: "#A1A1A6" },
  },
  shadow: "0 1px 2px rgba(29,29,31,.04), 0 8px 20px -12px rgba(29,29,31,.10)",
  well: "#F5F5F7",
};

const DARK: Palette = {
  ground: "#000000",
  ink: "#F5F5F7",
  ink2: "#A1A1A6",
  fills: {
    white: "#1C1C1E",
    tint: "#2C2C2E",
    sage: "#2C2C2E",
    sky: "#2C2C2E",
    brand: "#1F57C3",
    night: "#1C1C1E",
    widget: "#1C1C1E",
    widgetNight: "#000000",
  },
  onFill: {
    brand: { ink: "#FFFFFF", eyebrow: "#E8F0FF" },
  },
  shadow: "0 0 0 1px rgba(255,255,255,.06)",
  well: "#2C2C2E",
};

export function bentoPalette(slide: Slide): Palette {
  return slide.inverted ? DARK : LIGHT;
}

/** `[[phrase]]` marks the one gradient phrase in a Bento headline. */
export function BentoHeadline({
  text,
  fontSize,
  align,
  color,
  dark,
}: {
  text: string;
  fontSize: number;
  align: "left" | "center";
  color: string;
  dark: boolean;
}) {
  const gradient = dark
    ? "linear-gradient(90deg,#FF8A3D 0%,#FF4F7B 52%,#E15BD0 100%)"
    : "linear-gradient(90deg,#1F7A4D 0%,#0B6E8A 52%,#1F57C3 100%)";
  const lines = text.split("\n");
  return (
    <div
      style={{
        fontFamily: BENTO_FONT,
        fontWeight: 700,
        fontSize,
        lineHeight: 0.98,
        letterSpacing: "-0.035em",
        color,
        textAlign: align,
        whiteSpace: "pre",
      }}
    >
      {lines.map((line, lineIndex) => (
        <div key={lineIndex}>
          {line.split(/(\[\[[^\]]+\]\])/g).map((part, index) =>
            part.startsWith("[[") ? (
              <span
                key={index}
                style={{
                  backgroundImage: gradient,
                  WebkitBackgroundClip: "text",
                  backgroundClip: "text",
                  color: "transparent",
                  WebkitTextFillColor: "transparent",
                  paddingRight: "0.05em",
                  marginRight: "-0.05em",
                }}
              >
                {part.slice(2, -2)}
              </span>
            ) : (
              <span key={index}>{part}</span>
            ),
          )}
        </div>
      ))}
    </div>
  );
}

function Icon({ name, size, color }: { name: string; size: number; color: string }) {
  const Component = (Icons as unknown as Record<string, React.ComponentType<Icons.LucideProps>>)[name];
  if (!Component) return null;
  return <Component size={size} color={color} strokeWidth={2} absoluteStrokeWidth={false} />;
}

/** The stage tiles' fills, drawn under the device. */
export function BentoStageFills({ slide, cW }: { slide: Slide; cW: number }) {
  const s = cW / BASE_W;
  const palette = bentoPalette(slide);
  return (
    <>
      {(slide.tiles || [])
        .filter((tile) => tile.kind === "stage")
        .map((tile) => (
          <div
            key={tile.id}
            style={{
              position: "absolute",
              left: tile.x * s,
              top: tile.y * s,
              width: tile.w * s,
              height: tile.h * s,
              borderRadius: RADIUS * s,
              background: palette.fills[tile.fill],
              boxShadow: palette.shadow,
              zIndex: 1,
              pointerEvents: "none",
            }}
          />
        ))}
    </>
  );
}

/**
 * Ground-coloured cover with a stage-shaped hole, drawn above the device so
 * the stage tile crops the phone at its rounded edges.
 */
export function BentoStageMask({ slide, cW }: { slide: Slide; cW: number }) {
  const s = cW / BASE_W;
  const palette = bentoPalette(slide);
  const ground = slide.backgroundColor || palette.ground;
  return (
    <>
      {(slide.tiles || [])
        .filter((tile) => tile.kind === "stage")
        .map((tile) => (
          <div
            key={`${tile.id}-mask`}
            style={{
              position: "absolute",
              left: tile.x * s,
              top: tile.y * s,
              width: tile.w * s,
              height: tile.h * s,
              borderRadius: RADIUS * s,
              boxShadow: `0 0 0 ${Math.ceil(4000 * s)}px ${ground}`,
              zIndex: 3,
              pointerEvents: "none",
            }}
          />
        ))}
    </>
  );
}

/** Every non-stage tile, drawn above the device and its mask. */
export function BentoTiles({ slide, cW }: { slide: Slide; cW: number }) {
  const s = cW / BASE_W;
  const palette = bentoPalette(slide);
  return (
    <>
      {(slide.tiles || [])
        .filter((tile) => tile.kind !== "stage")
        .map((tile) => (
          <div
            key={tile.id}
            style={{
              position: "absolute",
              left: tile.x * s,
              top: tile.y * s,
              width: tile.w * s,
              height: tile.h * s,
              borderRadius: RADIUS * s,
              background: palette.fills[tile.fill],
              boxShadow: palette.shadow,
              overflow: "hidden",
              zIndex: 5,
              pointerEvents: "none",
            }}
          >
            <TileContent tile={tile} s={s} palette={palette} />
          </div>
        ))}
    </>
  );
}

function TileContent({ tile, s, palette }: { tile: BentoTile; s: number; palette: Palette }) {
  const on = palette.onFill[tile.fill];
  const ink = on?.ink ?? palette.ink;
  const eyebrowColor = on?.eyebrow ?? palette.ink2;
  const pad = (tile.h <= 300 ? 42 : PAD) * s;
  const eyebrow = tile.eyebrow ? (
    <div
      style={{
        fontFamily: TEXT_FONT,
        fontWeight: 600,
        fontSize: 31 * s,
        lineHeight: 1.1,
        letterSpacing: "-0.01em",
        color: eyebrowColor,
      }}
    >
      {tile.eyebrow}
    </div>
  ) : null;
  const caption = (text?: string) =>
    text ? (
      <div
        style={{
          fontFamily: TEXT_FONT,
          fontWeight: 600,
          fontSize: (tile.captionSize ?? 38) * s,
          lineHeight: 1.14,
          letterSpacing: "-0.018em",
          color: ink,
          marginTop: 14 * s,
        }}
      >
        {text}
      </div>
    ) : null;
  const box: React.CSSProperties = {
    position: "absolute",
    inset: pad,
    display: "flex",
    flexDirection: "column",
  };

  switch (tile.kind) {
    case "stat": {
      const size = (tile.valueSize ?? 200) * s;
      return (
        <div style={box}>
          {eyebrow}
          <div style={{ flex: 1 }} />
          <div style={{ display: "flex", alignItems: "baseline", gap: 12 * s }}>
            <span
              style={{
                fontFamily: BENTO_FONT,
                fontWeight: 700,
                fontSize: size,
                lineHeight: 0.8,
                letterSpacing: "-0.045em",
                color: ink,
              }}
            >
              {tile.value}
            </span>
            {tile.unit && (
              <span
                style={{
                  fontFamily: BENTO_FONT,
                  fontWeight: 700,
                  fontSize: size * 0.34,
                  lineHeight: 1,
                  letterSpacing: "-0.03em",
                  color: ink,
                }}
              >
                {tile.unit}
              </span>
            )}
          </div>
          {caption(tile.caption)}
        </div>
      );
    }
    case "icon":
      return (
        <div style={box}>
          <div
            style={{
              width: 104 * s,
              height: 104 * s,
              borderRadius: 30 * s,
              background: tile.fill === "white" ? palette.well : palette.fills.white,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <Icon name={tile.icon || "Sparkles"} size={58 * s} color={tile.iconColor || ink} />
          </div>
          <div style={{ flex: 1 }} />
          {eyebrow}
          <div
            style={{
              fontFamily: BENTO_FONT,
              fontWeight: 700,
              fontSize: (tile.labelSize ?? 64) * s,
              lineHeight: 1,
              letterSpacing: "-0.03em",
              color: ink,
              marginTop: tile.eyebrow ? 10 * s : 0,
              whiteSpace: "pre-line",
            }}
          >
            {tile.label}
          </div>
        </div>
      );
    case "inline":
      return (
        <div style={{ ...box, flexDirection: "row", alignItems: "center", gap: 32 * s }}>
          <div
            style={{
              width: 104 * s,
              height: 104 * s,
              flexShrink: 0,
              borderRadius: 30 * s,
              background: tile.fill === "white" ? palette.well : palette.fills.white,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <Icon name={tile.icon || "Sparkles"} size={58 * s} color={tile.iconColor || ink} />
          </div>
          <div
            style={{
              fontFamily: BENTO_FONT,
              fontWeight: 700,
              fontSize: (tile.labelSize ?? 52) * s,
              lineHeight: 1,
              letterSpacing: "-0.03em",
              color: ink,
            }}
          >
            {tile.label}
          </div>
        </div>
      );
    case "widget":
    case "image": {
      const source = tile.src ? img(tile.src) : undefined;
      return source ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={source}
          alt=""
          draggable={false}
          style={{
            position: "absolute",
            inset: (tile.inset ?? 0) * s,
            width: `calc(100% - ${2 * (tile.inset ?? 0) * s}px)`,
            height: `calc(100% - ${2 * (tile.inset ?? 0) * s}px)`,
            objectFit: tile.fit || (tile.kind === "widget" ? "contain" : "cover"),
            objectPosition: tile.objectPosition || "center",
            borderRadius: tile.inset ? (RADIUS - tile.inset) * s : 0,
          }}
        />
      ) : null;
    }
    case "list":
      return (
        <div style={box}>
          {eyebrow}
          <div style={{ marginTop: 18 * s }}>
            {(tile.items || []).map((item, index) => (
              <div
                key={item}
                style={{
                  fontFamily: BENTO_FONT,
                  fontWeight: 700,
                  fontSize: (tile.labelSize ?? 62) * s,
                  lineHeight: 1,
                  letterSpacing: "-0.03em",
                  color: ink,
                  padding: `${22 * s}px 0`,
                  borderTop: index === 0 ? "none" : `${2 * s}px solid rgba(29,29,31,.12)`,
                }}
              >
                {item}
              </div>
            ))}
          </div>
        </div>
      );
    case "identity": {
      const source = tile.src ? img(tile.src) : undefined;
      return (
        <div style={box}>
          {source && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={source}
              alt=""
              style={{
                width: 200 * s,
                height: 200 * s,
                borderRadius: 46 * s,
                boxShadow: `0 ${12 * s}px ${24 * s}px -${8 * s}px rgba(31,87,195,.35)`,
              }}
            />
          )}
          <div style={{ flex: 1 }} />
          <div
            style={{
              fontFamily: BENTO_FONT,
              fontWeight: 700,
              fontSize: (tile.labelSize ?? 72) * s,
              lineHeight: 1,
              letterSpacing: "-0.03em",
              color: ink,
            }}
          >
            {tile.label}
          </div>
          <div
            style={{
              fontFamily: TEXT_FONT,
              fontWeight: 600,
              fontSize: 32 * s,
              color: eyebrowColor,
              marginTop: 10 * s,
            }}
          >
            {tile.caption}
          </div>
        </div>
      );
    }
    case "bars": {
      const values = tile.values || [];
      const max = Math.max(1, ...values);
      return (
        <div style={box}>
          {eyebrow}
          <div style={{ flex: 1, display: "flex", alignItems: "flex-end", gap: 10 * s, marginTop: 20 * s }}>
            {values.map((value, index) => (
              <div
                key={index}
                style={{
                  flex: 1,
                  height: `${Math.max(6, (value / max) * 100)}%`,
                  borderRadius: 10 * s,
                  background: index === (tile.highlight ?? values.length - 1) ? palette.fills.brand : "rgba(29,29,31,.14)",
                }}
              />
            ))}
          </div>
          {caption(tile.caption)}
        </div>
      );
    }
    case "lock": {
      const source = tile.src ? img(tile.src) : undefined;
      return (
        <div style={{ ...box, alignItems: "center" }}>
          {eyebrow}
          <div
            style={{
              fontFamily: BENTO_FONT,
              fontWeight: 700,
              fontSize: (tile.valueSize ?? 150) * s,
              lineHeight: 1,
              letterSpacing: "-0.04em",
              color: ink,
              marginTop: 6 * s,
            }}
          >
            {tile.value}
          </div>
          {source && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={source}
              alt=""
              style={{ width: "100%", flex: 1, minHeight: 0, objectFit: "contain", marginTop: 16 * s }}
            />
          )}
        </div>
      );
    }
    default:
      return (
        <div style={box}>
          {eyebrow}
          <div style={{ flex: 1 }} />
          <div
            style={{
              fontFamily: BENTO_FONT,
              fontWeight: 700,
              fontSize: (tile.labelSize ?? 64) * s,
              lineHeight: 1.02,
              letterSpacing: "-0.03em",
              color: ink,
              whiteSpace: "pre-line",
            }}
          >
            {tile.label}
          </div>
          {caption(tile.caption)}
        </div>
      );
  }
}
