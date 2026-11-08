import fs from "node:fs";
const manifest: unknown = JSON.parse(fs.readFileSync("package.json", "utf8"));
if (
  manifest === null ||
  typeof manifest !== "object" ||
  !("dependencies" in manifest) ||
  manifest.dependencies === null ||
  typeof manifest.dependencies !== "object" ||
  Array.isArray(manifest.dependencies)
)
  throw new Error("Expected package dependency object");
Object.assign(manifest.dependencies, { "node-addon-api": "8.5.0" });
fs.writeFileSync("package.json", JSON.stringify(manifest, null, 2) + "\n");
