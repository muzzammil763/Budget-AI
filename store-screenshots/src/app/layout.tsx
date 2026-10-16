import type { Metadata } from "next";
import { Inter, Inter_Tight } from "next/font/google";
import "./globals.css";

const font = Inter({ subsets: ["latin"], variable: "--font-text" });
// Bento Keynote Grid display face (headlines, stats, tile labels).
const display = Inter_Tight({
  subsets: ["latin"],
  weight: ["600", "700"],
  variable: "--font-display",
  display: "block",
});

export const metadata: Metadata = {
  title: "App Store Screenshots",
  description: "Design and export App Store + Google Play screenshots.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={`${font.className} ${font.variable} ${display.variable}`}>{children}</body>
    </html>
  );
}
