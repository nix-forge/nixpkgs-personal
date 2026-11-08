import { createRequire } from "node:module";
import path from "node:path";
import { pathToFileURL } from "node:url";
const requirePackage = createRequire(
  path.join(process.cwd(), "backend", "package.json"),
);
interface SharpInput {
  create: {
    width: number;
    height: number;
    channels: number;
    background: string;
  };
}
interface Image {
  png(): unknown;
}
function sharpFactory(value: unknown): value is (input: SharpInput) => unknown {
  return typeof value === "function";
}
function imageEncoder(value: unknown): value is Image {
  return (
    value !== null &&
    typeof value === "object" &&
    "png" in value &&
    typeof value.png === "function"
  );
}
function bufferEncoder(
  value: unknown,
): value is { toBuffer(): Promise<unknown> } {
  return (
    value !== null &&
    typeof value === "object" &&
    "toBuffer" in value &&
    typeof value.toBuffer === "function"
  );
}
function databaseOpener(
  value: unknown,
): value is { open(file: string): unknown } {
  return (
    value !== null &&
    (typeof value === "object" || typeof value === "function") &&
    "open" in value &&
    typeof value.open === "function"
  );
}
async function main(): Promise<void> {
  requirePackage("better-sqlite3");
  requirePackage("bcrypt");
  const sharp: unknown = requirePackage("sharp");
  if (!sharpFactory(sharp)) throw new Error("Missing Sharp entrypoint");
  const image: unknown = sharp({
    create: { width: 1, height: 1, channels: 3, background: "#000000" },
  });
  if (!imageEncoder(image)) throw new Error("Missing Sharp PNG encoder");
  const png: unknown = image.png();
  if (!bufferEncoder(png)) throw new Error("Missing Sharp buffer encoder");
  const buffer: unknown = await png.toBuffer();
  if (!Buffer.isBuffer(buffer)) throw new Error("Invalid native image buffer");
  if (buffer.length === 0) throw new Error("empty native image");
  const module: unknown = await import(
    pathToFileURL(requirePackage.resolve("@russellthehippo/honker-node")).href
  );
  if (!module || typeof module !== "object" || !("default" in module))
    throw new Error("Missing Honker default export");
  const honker = module.default;
  if (!databaseOpener(honker))
    throw new Error("Missing Honker database opener");
  const temporary = process.env["TMPDIR"];
  if (!temporary) throw new Error("TMPDIR is required");
  honker.open(path.join(temporary, "aurral-smoke.db"));
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
