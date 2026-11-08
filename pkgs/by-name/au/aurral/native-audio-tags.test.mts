import * as api from "./test-api.mts";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const toImportSpecifier = (file: string): string => pathToFileURL(file).href;
const app = process.argv[2]!;
const run = promisify(execFile);
const temp = await fs.mkdtemp(path.join(os.tmpdir(), "aurral-native-tags-"));
const { writeAudioMetadata, readNativeAurralIdentity } = await api.load(
  toImportSpecifier(path.join(app, "backend/services/downloadUtils.ts")),
  api.audioWriter,
);
const { parseFile } = await api.load(
  toImportSpecifier(path.join(app, "node_modules/music-metadata/lib/index.js")),
  api.audioParser,
);
const metadata = {
  artistName: "Fixture artist",
  albumName: "Fixture album",
  trackName: "Fixture song",
  artistMbid: "00000000-0000-4000-8000-000000000001",
  albumMbid: "00000000-0000-4000-8000-000000000002",
  trackMbid: "00000000-0000-4000-8000-000000000003",
};
const release = "00000000-0000-4000-8000-000000000004";
const legacy = "AURRAL_IDS=" + JSON.stringify(metadata);
async function audioHash(file: string): Promise<string> {
  return (
    await run("ffmpeg", [
      "-v",
      "error",
      "-i",
      file,
      "-map",
      "0:a:0",
      "-c",
      "copy",
      "-f",
      "hash",
      "-",
    ])
  ).stdout;
}
try {
  for (const ext of ["flac", "mp3", "m4a"]) {
    const file = path.join(temp, "fixture." + ext);
    await run("ffmpeg", [
      "-v",
      "error",
      "-f",
      "lavfi",
      "-i",
      "sine=duration=0.15",
      "-metadata",
      "grouping=" + legacy,
      "-metadata",
      "comment=Keep this note",
      "-metadata",
      "musicbrainz_albumid=" + release,
      file,
    ]);
    await fs.chmod(file, 0o640);
    const hash = await audioHash(file);
    const original = await parseFile(file);
    await writeAudioMetadata(file, {});
    let migrated = await parseFile(file);
    assert.ok(!(migrated.common.grouping || "").includes("AURRAL_IDS="));
    assert.equal(
      readNativeAurralIdentity(migrated).artistMbid,
      metadata.artistMbid,
    );
    assert.equal(
      migrated.common.musicbrainz_albumid,
      original.common.musicbrainz_albumid,
    );
    assert.equal(await audioHash(file), hash);
    await writeAudioMetadata(file, metadata);
    let parsed = await parseFile(file);
    assert.ok(
      !(parsed.common.grouping || "").includes("AURRAL_IDS="),
      "internal IDs must not appear in grouping",
    );
    assert.equal(parsed.common.musicbrainz_artistid?.[0], metadata.artistMbid);
    assert.equal(parsed.common.musicbrainz_releasegroupid, metadata.albumMbid);
    assert.equal(parsed.common.musicbrainz_recordingid, metadata.trackMbid);
    assert.equal(parsed.common.title, metadata.trackName);
    assert.equal(parsed.common.album, metadata.albumName);
    assert.equal(
      readNativeAurralIdentity(parsed).artistMbid,
      metadata.artistMbid,
    );
    assert.equal(
      await audioHash(file),
      hash,
      "encoded audio must remain identical",
    );
    assert.equal((await fs.stat(file)).mode & 0o777, 0o640);
    assert.equal(
      parsed.common.musicbrainz_albumid,
      original.common.musicbrainz_albumid,
    );
    assert.ok(JSON.stringify(parsed.native).includes("Keep this note"));
    await writeAudioMetadata(file, { releaseMbid: release });
    await writeAudioMetadata(file, metadata);
    parsed = await parseFile(file);
    assert.equal(parsed.common.musicbrainz_albumid, release);
    assert.equal(await audioHash(file), hash);
    const originalIdentity = readNativeAurralIdentity(parsed);
    const replacementArtist = "00000000-0000-4000-8000-000000000005";
    await writeAudioMetadata(file, { artistMbid: replacementArtist });
    parsed = await parseFile(file);
    assert.deepEqual(
      readNativeAurralIdentity(parsed),
      { ...originalIdentity, artistMbid: replacementArtist },
      "a partial update preserves the other dedicated identity fields",
    );
    assert.equal(await audioHash(file), hash);
    if (ext === "flac") {
      const conflicting = path.join(temp, "conflicting.flac");
      await run("ffmpeg", [
        "-v",
        "error",
        "-i",
        file,
        "-c",
        "copy",
        "-metadata",
        "grouping=" + legacy,
        conflicting,
      ]);
      assert.equal(
        readNativeAurralIdentity(await parseFile(conflicting)).artistMbid,
        replacementArtist,
      );
      await writeAudioMetadata(conflicting, {});
      assert.equal(
        readNativeAurralIdentity(await parseFile(conflicting)).artistMbid,
        replacementArtist,
        "migration preserves dedicated identity over stale grouping",
      );
      assert.equal(await audioHash(conflicting), hash);
    }
    // A genuine user grouping must survive writing identities.
    const grouped = path.join(temp, "real-grouping." + ext);
    await run("ffmpeg", [
      "-v",
      "error",
      "-i",
      file,
      "-c",
      "copy",
      "-metadata",
      "grouping=Live performances",
      grouped,
    ]);
    await writeAudioMetadata(grouped, metadata);
    parsed = await parseFile(grouped);
    assert.equal(parsed.common.grouping, "Live performances");
  }
  console.log(
    "PASS: native identity tags round-trip without grouping pollution or audio changes",
  );
} finally {
  await fs.rm(temp, { recursive: true, force: true });
}
