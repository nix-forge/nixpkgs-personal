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
const temp = await fs.mkdtemp(
  path.join(os.tmpdir(), "aurral-lidarr-metadata-"),
);
process.env["AURRAL_DATA_DIR"] = path.join(temp, "data");
const { scanMusicRoot } = await api.load(
  toImportSpecifier(path.join(app, "backend/services/libraryFileScanner.ts")),
  api.fileScanner,
);
const { getLidarrMetadataByPath } = await api.load(
  toImportSpecifier(path.join(app, "backend/services/libraryIndexService.ts")),
  api.indexService,
);
const { db } = await api.load(
  toImportSpecifier(path.join(app, "backend/config/db-sqlite.ts")),
  api.database,
);
const { SCHEDULED_SYSTEM_TASKS, closeHonkerDb } = await api.load(
  toImportSpecifier(path.join(app, "backend/services/honkerDb.ts")),
  api.honker,
);
const { processSystemTask } = await api.load(
  toImportSpecifier(path.join(app, "backend/services/systemTaskWorker.ts")),
  api.systemWorker,
);
const { getScheduledLibraryScanJobId, stopLibraryScanWorker } = await api.load(
  toImportSpecifier(path.join(app, "backend/services/libraryScanWorker.ts")),
  api.scanWorker,
);
const rootPath = path.join(temp, "music");
const filePath = path.join(rootPath, "Artist", "Album", "01 Track.flac");
await fs.mkdir(path.dirname(filePath), { recursive: true });
await fs.writeFile(filePath, "fixture");

let metadataReads = 0;
const metadataReader = async () => {
  metadataReads += 1;
  return {
    common: {
      albumartist: "Artist",
      album: "Album",
      title: "Track",
      track: { no: 1 },
    },
    format: { duration: 180 },
  };
};
const scan = (
  metadataEnricher: ((source: unknown, file: string) => unknown) | null,
  force = false,
) =>
  scanMusicRoot({
    rootPath,
    source: "lidarr",
    force,
    metadataReader,
    metadataEnricher,
    metadataLookup: metadataEnricher
      ? (lookupPath: string) => metadataEnricher(null, lookupPath)
      : null,
  });
const lidarrMetadata = () => ({
  artistMbid: "00000000-0000-4000-8000-000000000001",
  albumMbid: "00000000-0000-4000-8000-000000000002",
  trackMbid: "00000000-0000-4000-8000-000000000003",
  foreignAlbumId: "00000000-0000-4000-8000-000000000002",
  images: [{ remoteUrl: "https://example.invalid/cover.jpg" }],
});
try {
  const { writeAudioMetadata } = await api.load(
    toImportSpecifier(path.join(app, "backend/services/downloadUtils.ts")),
    api.audioWriter,
  );
  const { parseFile } = await api.load(
    toImportSpecifier(
      path.join(app, "node_modules/music-metadata/lib/index.js"),
    ),
    api.audioParser,
  );
  const audio = path.join(temp, "identity.flac");
  const releaseId = "00000000-0000-4000-8000-000000000010";
  const groupId = "00000000-0000-4000-8000-000000000011";
  await promisify(execFile)("ffmpeg", [
    "-hide_banner",
    "-loglevel",
    "error",
    "-f",
    "lavfi",
    "-i",
    "anullsrc=r=44100:cl=stereo",
    "-t",
    "0.1",
    "-c:a",
    "flac",
    "-metadata",
    `musicbrainz_albumid=${releaseId}`,
    audio,
  ]);
  await writeAudioMetadata(audio, { albumName: "Album", albumMbid: groupId });
  let tagged = await parseFile(audio);
  assert.equal(
    tagged.common.musicbrainz_albumid,
    releaseId,
    "release-group identity must not overwrite a specific release ID",
  );
  assert.equal(tagged.common.musicbrainz_releasegroupid, groupId);
  const replacementRelease = "00000000-0000-4000-8000-000000000012";
  await writeAudioMetadata(audio, {
    albumMbid: groupId,
    releaseMbid: replacementRelease,
  });
  tagged = await parseFile(audio);
  assert.equal(tagged.common.musicbrainz_albumid, replacementRelease);
  assert.equal(tagged.common.musicbrainz_releasegroupid, groupId);
  assert.equal(
    SCHEDULED_SYSTEM_TASKS.find(
      (task: { name: string }) => task["name"] === "library-index-refresh",
    )?.schedule,
    "@every 6h",
  );
  await processSystemTask({ kind: "library-index-refresh" });
  assert.ok(getScheduledLibraryScanJobId() > 0);
  const imported = await getLidarrMetadataByPath(
    {
      isConfigured: () => true,
      getArtists: async (options: { forceRefresh: boolean }) => {
        assert.equal(options.forceRefresh, true);
        return [{ id: 1, foreignArtistId: "artist-id" }];
      },
      getAllAlbums: async ({ forceRefresh }: { forceRefresh: boolean }) => {
        assert.equal(forceRefresh, true);
        return [
          {
            id: 2,
            artistId: 1,
            foreignAlbumId: "album-id",
            images: [{ remoteUrl: "https://example.invalid/cover.jpg" }],
          },
        ];
      },
      getAllTracks: async () => [
        {
          id: 3,
          albumId: 2,
          trackFileId: 4,
          foreignRecordingId: "recording-id",
        },
      ],
      getTrackFilesByIds: async () => [{ id: 4, path: filePath }],
    },
    { forceRefresh: true },
  );
  assert.equal(imported.size, 1);
  assert.equal(api.present(imported.get(filePath)).albumMbid, "album-id");
  assert.equal(imported.get(path.join(rootPath, "other.flac")), undefined);
  await scan(null);
  const before = api.present(
    db.prepare("SELECT id, identity_key FROM library_albums").get(),
  );
  assert.ok(before);
  await scan(lidarrMetadata);
  await scan(lidarrMetadata);
  assert.equal(metadataReads, 2);
  const album = api.present(db.prepare("SELECT * FROM library_albums").get());
  const artist = api.present(db.prepare("SELECT * FROM library_artists").get());
  const track = api.present(db.prepare("SELECT * FROM library_tracks").get());
  assert.equal(album["id"], before["id"]);
  assert.equal(album["identity_key"], before["identity_key"]);
  assert.equal(
    album["release_group_mbid"],
    "00000000-0000-4000-8000-000000000002",
  );
  assert.equal(
    album["mbid"],
    null,
    "a release-group ID from Lidarr must not become an individual release ID",
  );
  assert.equal(artist["mbid"], "00000000-0000-4000-8000-000000000001");
  assert.equal(track["mbid"], "00000000-0000-4000-8000-000000000003");
  assert.equal(
    api.record(
      api.array(
        api.record(JSON.parse(api.string(album["metadata_json"])))["images"],
      )[0],
    )["remoteUrl"],
    "https://example.invalid/cover.jpg",
  );
  for (const table of [
    "library_artists",
    "library_albums",
    "library_tracks",
    "library_media_files",
  ]) {
    assert.equal(
      api.present(db.prepare(`SELECT COUNT(*) AS total FROM ${table}`).get())[
        "total"
      ],
      1,
    );
  }

  // An upgrade must repair IDs already persisted by the previous enrichment.
  db.prepare(
    "UPDATE library_albums SET mbid = release_group_mbid WHERE id = ?",
  ).run(before["id"]);
  await scan(lidarrMetadata);
  const repaired = api.present(
    db.prepare("SELECT * FROM library_albums WHERE id = ?").get(before["id"]),
  );
  assert.equal(repaired["mbid"], null);
  assert.equal(repaired["identity_key"], before["identity_key"]);
  assert.equal(
    metadataReads,
    3,
    "unchanged files with legacy IDs are revisited",
  );
  await scan(lidarrMetadata);
  assert.equal(
    metadataReads,
    3,
    "the repaired file is skipped on the next scan",
  );
  db.prepare("UPDATE library_albums SET mbid = ? WHERE id = ?").run(
    releaseId,
    before["id"],
  );
  await scan(lidarrMetadata, true);
  assert.equal(
    api.present(
      db
        .prepare("SELECT mbid FROM library_albums WHERE id = ?")
        .get(before["id"]),
    )["mbid"],
    releaseId,
    "a real release ID survives the repair",
  );

  const downloadRoot = path.join(temp, "aurral-downloads");
  const downloadPath = path.join(
    downloadRoot,
    "Other Artist",
    "Other Album",
    "01 Song.flac",
  );
  await fs.mkdir(path.dirname(downloadPath), { recursive: true });
  await fs.writeFile(downloadPath, "fixture");
  const scanDownload = (enrichment: Record<string, string> | null) =>
    scanMusicRoot({
      rootPath: downloadRoot,
      source: "aurral",
      metadataReader: async () => ({
        common: {
          albumartist: "Other Artist",
          album: "Other Album",
          title: "Song",
          grouping:
            "AURRAL_IDS=" +
            JSON.stringify({
              artistMbid: "00000000-0000-4000-8000-000000000008",
            }),
        },
        native: {
          vorbis: [
            {
              id: "AURRAL_IDS",
              value:
                "AURRAL_IDS=" +
                JSON.stringify({
                  artistMbid: "00000000-0000-4000-8000-000000000007",
                }),
            },
          ],
        },
        format: { duration: 120 },
      }),
      metadataEnricher: () => enrichment,
      metadataLookup: () => enrichment,
    });
  await scanDownload(null);
  assert.equal(
    api.present(
      db
        .prepare("SELECT mbid FROM library_artists WHERE name = 'Other Artist'")
        .get(),
    )["mbid"],
    "00000000-0000-4000-8000-000000000007",
    "dedicated identity tags take precedence over conflicting legacy grouping",
  );
  await scanDownload({
    artistMbid: "00000000-0000-4000-8000-000000000004",
    albumMbid: "00000000-0000-4000-8000-000000000005",
    trackMbid: "00000000-0000-4000-8000-000000000006",
  });
  const downloaded = api.present(
    db
      .prepare(
        `
    SELECT artist.mbid AS artist_mbid, album.release_group_mbid AS album_mbid,
      track.mbid AS track_mbid
    FROM library_media_files AS file
    JOIN library_albums AS album ON album.id = file.album_id
    JOIN library_artists AS artist ON artist.id = album.artist_id
    JOIN library_tracks AS track ON track.id = file.track_id
    WHERE file.source = 'aurral' AND file.path = ? AND file.available = 1
  `,
      )
      .get(downloadPath),
  );
  assert.equal(
    downloaded["artist_mbid"],
    "00000000-0000-4000-8000-000000000004",
  );
  assert.equal(
    downloaded["album_mbid"],
    "00000000-0000-4000-8000-000000000005",
  );
  assert.equal(
    downloaded["track_mbid"],
    "00000000-0000-4000-8000-000000000006",
  );
} finally {
  await stopLibraryScanWorker();
  closeHonkerDb();
  db.close();
  await fs.rm(temp, { recursive: true, force: true });
}
process.exit(0);
