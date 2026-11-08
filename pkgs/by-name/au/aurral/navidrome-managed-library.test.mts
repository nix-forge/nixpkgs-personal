import assert from "node:assert/strict";
import * as api from "./test-api.mts";
const app = process.argv[2];
assert.ok(app);
process.env["AURRAL_NAVIDROME_MANAGED_LIBRARY"] = "true";
try {
  const { NavidromeClient } = await api.load(
    `${app}/backend/services/navidrome.ts`,
    api.navidrome,
  );
  const client = new NavidromeClient(
    "http://fixture.invalid",
    "regular",
    "fixture-password",
  );
  const calls: string[] = [];
  client["_nativeRequest"] = async () => {
    throw new Error("Administrator API must never be called");
  };
  client.request = async (endpoint: string) => {
    calls.push(endpoint);
    assert.equal(endpoint, "getMusicFolders");
    return { musicFolders: { musicFolder: [{ id: "1", name: "Music" }] } };
  };
  assert.deepEqual(await client.ensureAurralLibrary("/media/music/"), {
    name: "Aurral Playlists",
    path: "/media/music",
  });
  client["_songsByFile"].set("fixture", {});
  await client.scanLibrary();
  assert.equal(client["_songsByFile"].size, 0);
  assert.deepEqual(calls, ["getMusicFolders"]);
  client.request = async () => ({ musicFolders: { musicFolder: [] } });
  await assert.rejects(
    client.ensureAurralLibrary("/media/music"),
    /No readable managed/,
  );
  client.request = async () => {
    throw new Error("Authentication failed");
  };
  await assert.rejects(
    client.ensureAurralLibrary("/media/music"),
    /Authentication failed/,
  );
  client.request = async () => ({ user: { adminRole: false } });
  await assert.rejects(
    client.getPlaylistTrackPaths(),
    /requires an admin account/,
  );
  delete process.env["AURRAL_NAVIDROME_MANAGED_LIBRARY"];
  client["_nativeRequest"] = async () => {
    throw new Error("Original admin lifecycle preserved");
  };
  await assert.rejects(
    client.ensureAurralLibrary("/media/music"),
    /Original admin lifecycle/,
  );
  console.log("managed Navidrome library access cases passed");
} finally {
  delete process.env["AURRAL_NAVIDROME_MANAGED_LIBRARY"];
}
