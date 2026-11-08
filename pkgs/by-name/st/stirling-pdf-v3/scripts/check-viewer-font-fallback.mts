import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

// Exercise the release artifact, including its embedded worker implementation.
const assetPath = process.argv[2];
assert.ok(assetPath);
const asset = readFileSync(assetPath, "utf8");
assert.equal(
  createHash("sha256").update(asset).digest("hex"),
  "8908728266b5f07b6358de589ed8b31f9d66e9fe366d0bffb72f2b2a44aab3b3",
  "Review the released viewer before changing the pinned asset",
);
const anchor = "class FontFallbackManager {";
assert.equal(asset.split(anchor).length, 2);
const start = asset.indexOf(anchor);
const end = asset.indexOf("\n}", start);
assert.ok(end > start);
const source = asset
  .slice(start, end + 2)
  .replaceAll("\\`", "`")
  .replaceAll("\\${", "${");
type FontManager = {
  mapFont(
    weight: number,
    italic: number,
    charset: number,
    flags: number,
    face: string,
  ): number;
  fontHandles: { get(id: number): { url: string } | undefined };
};
const isRecord = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object";
const isFontConstructor = (
  value: unknown,
): value is new (config: unknown, logger: unknown) => unknown =>
  typeof value === "function";
const isFontManager = (value: unknown): value is FontManager =>
  isRecord(value) &&
  typeof value["mapFont"] === "function" &&
  isRecord(value["fontHandles"]) &&
  typeof value["fontHandles"]["get"] === "function";
const FontFallbackManager: unknown = runInNewContext(`(${source})`, {
  LOG_SOURCE$2: "pdfium",
  LOG_CATEGORY$2: "font-fallback",
});
assert.ok(isFontConstructor(FontFallbackManager));
const variants = (family: string) => [
  { url: `${family}-Regular.ttf`, weight: 400 },
  { url: `${family}-Bold.ttf`, weight: 700 },
  { url: `${family}-Italic.ttf`, weight: 400, italic: true },
  { url: `${family}-BoldItalic.ttf`, weight: 700, italic: true },
];
const latin = variants("LiberationSans");
const manager = new FontFallbackManager(
  {
    baseUrl: "/fonts",
    defaultFont: "NotoSans-Regular.ttf",
    fonts: {
      0: latin,
      1: latin,
      161: latin,
      178: "NotoSansArabic-Regular.ttf",
    },
    fontFamilies: {
      serif: variants("LiberationSerif"),
      monospace: variants("LiberationMono"),
      wide: "DejaVuSans.ttf",
    },
  },
  { debug() {}, warn() {}, info() {}, error() {} },
);
assert.ok(isFontManager(manager));
const selected = (
  face: string,
  charset = 0,
  flags = 0,
  weight = 400,
  italic = 0,
) => {
  const handle = manager.mapFont(weight, italic, charset, flags, face);
  return manager.fontHandles.get(handle)?.url;
};
assert.equal(selected("Times-Roman"), "/fonts/LiberationSerif-Regular.ttf");
assert.equal(
  selected("ABCDEF+CourierNewPSMT"),
  "/fonts/LiberationMono-Regular.ttf",
);
assert.equal(selected("Helvetica"), "/fonts/LiberationSans-Regular.ttf");
assert.equal(
  selected("NotoSansMono-Regular"),
  "/fonts/LiberationMono-Regular.ttf",
);
assert.equal(selected("CenturyGothic"), "/fonts/LiberationSans-Regular.ttf");
assert.equal(selected("Verdana"), "/fonts/DejaVuSans.ttf");
assert.equal(selected("Unknown", 0, 16), "/fonts/LiberationSerif-Regular.ttf");
assert.equal(selected("Unknown", 161, 1), "/fonts/LiberationMono-Regular.ttf");
assert.equal(
  selected("Times-Roman", 0, 0, 700, 1),
  "/fonts/LiberationSerif-BoldItalic.ttf",
);
assert.equal(
  selected("Times-Roman", 178, 16),
  "/fonts/NotoSansArabic-Regular.ttf",
);
console.log("Released viewer font selection: 10 cases passed");
