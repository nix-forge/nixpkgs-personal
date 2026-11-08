import fs from "node:fs";
const version = process.argv[2];
if (!version) throw new Error("Expected package version argument");
const manifest: unknown = JSON.parse(fs.readFileSync("package.json", "utf8"));
if (
  manifest === null ||
  typeof manifest !== "object" ||
  !("version" in manifest) ||
  manifest.version !== version
)
  process.exit(1);
