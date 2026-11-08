import * as api from "./test-api.mts";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const toImportSpecifier = (file: string): string => pathToFileURL(file).href;

const app = process.argv[2]!;
const temp = await fs.mkdtemp(
  path.join(os.tmpdir(), "aurral-listenbrainz-test-"),
);
process.env["AURRAL_DATA_DIR"] = path.join(temp, "data");
try {
  const {
    getListenbrainzRecordingCharts,
    getListenbrainzRecommendedPlaylists,
    normalizeRecording,
    normalizeReleaseGroup,
    coverForRelease,
  } = await api.load(
    toImportSpecifier(
      path.join(app, "backend/services/discovery/listenbrainzCharts.js"),
    ),
    api.charts,
  );
  const { mergeRetainedRecommendationPool } = await api.load(
    toImportSpecifier(
      path.join(app, "backend/services/discovery/recommendationPipeline.ts"),
    ),
    api.recommendations,
  );
  assert.equal(normalizeRecording({ artist_name: "A" }), null);
  const profile = {
    listenHistoryProvider: "listenbrainz",
    listenHistoryUsername: "user name",
  };
  const playlistId = "00000000-0000-4000-8000-000000000010";
  const releaseId = "00000000-0000-4000-8000-000000000004";
  const paths: [string, Record<string, unknown>][] = [];
  const charts = await getListenbrainzRecordingCharts(profile, {
    count: 200,
    request: async (url: string, params: Record<string, unknown>) => {
      paths.push([url, params]);
      if (url.includes("release-groups"))
        return {
          payload: {
            release_groups: [
              {
                artist_name: "Artist",
                release_group_name: "Album",
                release_group_mbid: releaseId,
                caa_release_mbid: releaseId,
                listen_count: 42,
              },
            ],
          },
        };
      if (url.includes("/playlists/recommendations"))
        return {
          playlists: [
            {
              playlist: {
                identifier: `https://listenbrainz.org/playlist/${playlistId}`,
                title: "Weekly Jams",
              },
            },
          ],
        };
      if (url.includes(`/playlist/${playlistId}`))
        return {
          playlist: {
            track: [
              {
                creator: "Artist",
                title: "Suggested",
                album: "Album",
                extension: {
                  "https://musicbrainz.org/doc/jspf#track": {
                    release_identifier: `https://musicbrainz.org/release/${releaseId}`,
                  },
                },
              },
            ],
          },
        };
      return {
        payload: {
          recordings: [
            {
              artist_name: " Artist ",
              track_name: " Track ",
              recording_mbid: "recording",
              release_mbid: "release",
              listen_count: 12,
            },
            { artist_name: "", track_name: "invalid" },
          ],
        },
      };
    },
  });
  assert.equal(charts.global.length, 1);
  assert.equal(charts.personal.length, 1);
  assert.equal(api.present(charts.global[0]).artistName, "Artist");
  assert.equal(api.present(charts.personal[0]).listenCount, 12);
  assert.equal(api.present(charts.personal[0]).albumMbid, null);
  assert.equal(api.present(charts.personal[0]).releaseMbid, "release");
  assert.equal(api.present(charts.global[0]).coverUrl, null);
  assert.equal(
    api.present(
      normalizeRecording({
        artist_name: "A",
        track_name: "T",
        release_mbid: "00000000-0000-4000-8000-000000000007",
        caa_release_mbid: releaseId,
      }),
    ).coverUrl,
    coverForRelease(releaseId),
  );
  assert.equal(normalizeReleaseGroup({ artist_name: "A" }), null);
  assert.equal(
    coverForRelease(releaseId),
    `https://coverartarchive.org/release/${releaseId}/front-1200`,
  );
  assert.equal(coverForRelease("bad-id"), null);
  assert.equal(
    api.present(
      normalizeReleaseGroup({
        artist_name: "A",
        release_group_name: "Album",
        release_group_mbid: releaseId,
        caa_release_mbid: "00000000-0000-4000-8000-000000000007",
      }),
    ).coverUrl,
    `https://coverartarchive.org/release-group/${releaseId}/front-1200`,
  );
  assert.equal(
    api.present(
      normalizeReleaseGroup({
        artist_name: "A",
        release_group_name: "Album",
        caa_release_mbid: releaseId,
      }),
    ).name,
    "Album",
  );
  assert.equal(api.present(charts.trendingAlbums[0]).name, "Album");
  assert.equal(api.present(charts.trendingAlbums[0]).listenCount, 42);
  assert.equal(api.present(charts.recommendedTracks[0]).trackName, "Suggested");
  assert.equal(
    api.present(charts.recommendedTracks[0]).coverUrl,
    coverForRelease(releaseId),
  );
  const fallbackCharts = await getListenbrainzRecordingCharts(profile, {
    count: 10,
    recommendedArtists: [
      { id: "00000000-0000-4000-8000-000000000008", name: "New Artist" },
    ],
    request: async (url: string) => {
      if (url.includes("/listens"))
        return {
          payload: {
            listens: [
              {
                listened_at: 12,
                track_metadata: {
                  artist_name: "Played Artist",
                  track_name: "Played Song",
                  mbid_mapping: {
                    recording_mbid: "00000000-0000-4000-8000-000000000009",
                    caa_release_mbid: releaseId,
                  },
                },
              },
              {
                listened_at: 11,
                track_metadata: {
                  artist_name: "Played Artist",
                  track_name: "Played Song",
                },
              },
            ],
          },
        };
      if (url.includes("/popularity/top-recordings-for-artist/"))
        return [
          {
            artist_name: "New Artist",
            recording_name: "New Song",
            recording_mbid: "00000000-0000-4000-8000-000000000011",
            caa_release_mbid: releaseId,
            total_listen_count: 99,
          },
        ];
      return null;
    },
  });
  assert.equal(
    api.present(fallbackCharts.personal[0]).trackName,
    "Played Song",
  );
  assert.equal(api.present(fallbackCharts.personal[0]).listenCount, 2);
  assert.equal(
    api.present(fallbackCharts.personal[0]).coverUrl,
    coverForRelease(releaseId),
  );
  assert.equal(fallbackCharts.personalRange, "recent");
  assert.equal(
    api.present(fallbackCharts.recommendedTracks[0]).trackName,
    "New Song",
  );
  assert.equal(
    api.present(fallbackCharts.recommendedTracks[0]).coverUrl,
    coverForRelease(releaseId),
  );
  assert.equal(fallbackCharts.recommendedSource, "artist-popularity");
  assert.ok(paths[0] && paths[1]);
  assert.equal(paths[0][1]["count"], 50);
  assert.match(paths[1][0], /user\/user%20name\/recordings/);

  const playlists = await getListenbrainzRecommendedPlaylists(profile, {
    request: async (url: string) =>
      url.includes("/playlists/recommendations")
        ? {
            playlists: [
              {
                playlist: {
                  identifier: `https://listenbrainz.org/playlist/${playlistId}`,
                  title: "Weekly Jams",
                },
              },
            ],
          }
        : {
            playlist: {
              track: [{ creator: "Artist", title: "Recommended Song" }],
            },
          },
  });
  assert.equal(playlists.length, 1);
  assert.equal(api.present(playlists[0]).name, "Weekly Jams");
  assert.equal(
    api.present(api.present(playlists[0]).tracks[0]).trackName,
    "Recommended Song",
  );

  assert.equal(charts.unavailable, false);
  const unavailable = await getListenbrainzRecordingCharts(profile, {
    request: async () => {
      throw new Error("provider cooldown");
    },
  });
  assert.equal(unavailable.unavailable, true);
  assert.equal(unavailable.global.length, 0);
  assert.equal(unavailable.personal.length, 0);

  const ranked = mergeRetainedRecommendationPool({
    freshRecommendations: [
      {
        id: "00000000-0000-4000-8000-000000000005",
        name: "A weak match",
        scoreTagAffinity: 10,
      },
      {
        id: "00000000-0000-4000-8000-000000000006",
        name: "Z strong match",
        scoreTagAffinity: 100,
      },
    ],
    runStartedAt: "2026-01-01T00:00:00.000Z",
  });
  assert.equal(api.present(ranked[0]).name, "Z strong match");
} finally {
  await fs.rm(temp, { recursive: true, force: true });
}
