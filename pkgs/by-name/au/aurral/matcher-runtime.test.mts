import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import * as api from "./test-api.mts";
const app = api.present(process.argv[2]);
const matcher = await api.load(
  pathToFileURL(`${app}/backend/services/trackMatching/nativeMatcher.ts`).href,
  api.nativeMatcher,
);
assert.equal(matcher.getMatcherStatus().available, true);
const requested = {
  title: "Fixture Track",
  artists: ["Fixture Artist"],
  durationMs: 180000,
};
const exact = matcher.decideRecording(requested, [
  { title: "Fixture Track", artists: ["Fixture Artist"], durationMs: 180000 },
]);
assert.equal(exact.decision, "selectable");
assert.equal(exact.selectedIndex, 0);
const conflicting = matcher.decideRecording(requested, [
  { title: "Other Song (Live)", artists: ["Other Artist"], durationMs: 240000 },
]);
assert.equal(conflicting.decision, "skip");
assert.equal(conflicting.selectedIndex, null);
console.log(
  "Native matcher accepts exact recordings and rejects conflicting evidence",
);
