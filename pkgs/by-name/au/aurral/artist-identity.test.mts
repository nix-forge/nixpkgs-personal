import * as api from "./test-api.mts";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
const app = process.argv[2];
const temp = await fs.mkdtemp(
  path.join(os.tmpdir(), "aurral-artist-identity-"),
);
process.env["AURRAL_DATA_DIR"] = temp;
const { db } = await api.load(
  `${app}/backend/config/db-sqlite.ts`,
  api.database,
);
const store = await api.load(
  `${app}/backend/services/libraryMediaStore.ts`,
  api.mediaStore,
);
const { closeHonkerDb } = await api.load(
  `${app}/backend/services/honkerDb.ts`,
  api.honker,
);
const { userOps } = await api.load(
  `${app}/backend/db/helpers/index.ts`,
  api.users,
);
const { hashPassword } = await api.load(
  `${app}/backend/middleware/passwordHash.ts`,
  api.password,
);
const mbid = "11111111-1111-4111-8111-111111111111";
const key = `mbid:${mbid}`;
const legacyKey = "name:artist:fixture artist";
try {
  const legacy = store.upsertLibraryArtist({
    identityKey: legacyKey,
    mbid,
    name: "Fixture Artist",
  });
  const album = store.upsertLibraryAlbum({
    identityKey: "album:fixture",
    artistId: legacy.id,
    title: "Fixture Album",
  });
  const user = userOps.createUser(
    "fixture",
    hashPassword("fixture-password"),
    "admin",
  );
  db.prepare("INSERT INTO subsonic_stars VALUES (?, 'artist', ?, ?)").run(
    user.id,
    legacyKey,
    Date.now(),
  );
  db.prepare(
    "INSERT INTO library_management (entity_kind,entity_id,managed_by,monitor_mode,created_at,updated_at) VALUES ('artist', ?, 'lidarr', 'all', 1, 1)",
  ).run(legacy.id);
  const management = await api.load(
    `${app}/backend/services/libraryManagementStore.ts`,
    api.management,
  );
  assert.equal(management.getManagedBy("artist", legacy.id), "lidarr");
  const resolved = store.upsertLibraryArtist({
    identityKey: key,
    mbid,
    name: "Fixture Artist",
  });
  assert.equal(
    api.present(
      db
        .prepare("SELECT count(*) AS n FROM library_artists WHERE mbid=?")
        .get(mbid),
    )["n"],
    1,
    "an enriched name-based artist must be promoted instead of duplicated",
  );
  assert.equal(
    api.present(
      db
        .prepare("SELECT artist_id FROM library_albums WHERE id=?")
        .get(album.id),
    )["artist_id"],
    resolved.id,
  );
  assert.equal(
    api.present(
      db
        .prepare("SELECT entity_key FROM subsonic_stars WHERE user_id=?")
        .get(user.id),
    )["entity_key"],
    key,
  );
  assert.equal(
    management.getManagedBy("artist", resolved.id),
    "lidarr",
    "management survives promotion",
  );
  // Reproduce an already persisted duplicate with an alias, as found in older libraries.
  const inserted = db
    .prepare(
      "INSERT INTO library_artists(identity_key,mbid,name,created_at,updated_at) VALUES (?,?,?,?,?)",
    )
    .run("name:artist:old alias", mbid, "Old Alias", 1, 1);
  const second = store.upsertLibraryAlbum({
    identityKey: "album:second",
    artistId: Number(inserted.lastInsertRowid),
    title: "Second",
  });
  db.prepare(
    "INSERT INTO library_management (entity_kind,entity_id,managed_by,monitor_mode,created_at,updated_at) VALUES ('artist', ?, 'aurral', 'none', 1, 1)",
  ).run(Number(inserted.lastInsertRowid));
  assert.equal(
    management.getManagedBy("artist", Number(inserted.lastInsertRowid)),
    "aurral",
  );
  store.repairLibraryArtistIdentities();
  assert.equal(
    api.present(
      db
        .prepare("SELECT count(*) AS n FROM library_artists WHERE mbid=?")
        .get(mbid),
    )["n"],
    1,
  );
  assert.equal(
    api.present(
      db
        .prepare("SELECT artist_id FROM library_albums WHERE id=?")
        .get(second.id),
    )["artist_id"],
    resolved.id,
  );
  assert.equal(
    management.getManagedBy("artist", resolved.id),
    "lidarr",
    "an existing canonical management setting takes precedence",
  );
  assert.equal(
    management.getManagedBy("artist", Number(inserted.lastInsertRowid)),
    null,
    "the deleted artist's cached management setting is invalidated",
  );
  assert.equal(
    api.present(
      db
        .prepare(
          "SELECT count(*) AS n FROM library_search_documents WHERE entity_kind='artist' AND entity_id=?",
        )
        .get(Number(inserted.lastInsertRowid)),
    )["n"],
    0,
  );
  assert.equal(
    api.present(
      db
        .prepare("SELECT name FROM library_artists WHERE id=?")
        .get(resolved.id),
    )["name"],
    "Fixture Artist",
    "repair retains resolved metadata",
  );
  const other = store.upsertLibraryArtist({
    identityKey: "mbid:22222222-2222-4222-8222-222222222222",
    mbid: "22222222-2222-4222-8222-222222222222",
    name: "Fixture Artist",
  });
  assert.notEqual(
    other.id,
    resolved.id,
    "distinct MusicBrainz artists with the same name must remain separate",
  );
  store.repairLibraryArtistIdentities();
  assert.equal(
    api.present(db.prepare("SELECT count(*) AS n FROM library_artists").get())[
      "n"
    ],
    2,
    "repair is repeatable and does not merge by name alone",
  );
  console.log(
    "PASS: identity promotion, persisted duplicate repair, albums, stars, search and same-name isolation",
  );
} finally {
  closeHonkerDb();
  db.close();
  await fs.rm(temp, { recursive: true, force: true });
}
