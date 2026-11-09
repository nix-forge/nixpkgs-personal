import fs from "node:fs";
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
const policyFile = process.argv[2];
if (!policyFile) throw new Error("Pass the reviewed dependency policy");
const policy: unknown = JSON.parse(fs.readFileSync(policyFile, "utf8"));
if (!isRecord(policy)) throw new Error("Expected dependency policy object");
for (const field of ["dependencies", "devDependencies", "overrides"]) {
  const entries = policy[field];
  if (
    !isRecord(entries) ||
    !Object.values(entries).every((value) => typeof value === "string")
  ) {
    throw new Error("Expected flat string dependency policy: " + field);
  }
}
const manifest: unknown = JSON.parse(fs.readFileSync("package.json", "utf8"));
if (
  !isRecord(manifest) ||
  !isRecord(manifest["dependencies"]) ||
  !isRecord(manifest["devDependencies"]) ||
  "overrides" in manifest
)
  throw new Error("Expected upstream dependency objects without overrides");
Object.assign(manifest["dependencies"], policy["dependencies"]);
Object.assign(manifest["devDependencies"], policy["devDependencies"]);
manifest["overrides"] = policy["overrides"];
fs.writeFileSync("package.json", JSON.stringify(manifest, null, 2) + "\n");
