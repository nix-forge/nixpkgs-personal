import fs = require("node:fs");
import crypto = require("node:crypto");

const address = crypto.randomBytes(6);
address[0] = 2;
let digits;
do {
  digits = String(crypto.randomInt(100000000)).padStart(8, "0");
} while (
  /^(\d)\1{7}$/.test(digits) ||
  ["12345678", "87654321"].includes(digits)
);

const bridge = {
  username: [...address]
    .map((x) => x.toString(16).padStart(2, "0"))
    .join(":")
    .toUpperCase(),
  pin: `${digits.slice(0, 3)}-${digits.slice(3, 5)}-${digits.slice(5)}`,
};

fs.writeFileSync(
  process.argv[2]!,
  JSON.stringify({ bridge, platforms: [], accessories: [] }),
  { mode: 0o600, flag: "wx" },
);
