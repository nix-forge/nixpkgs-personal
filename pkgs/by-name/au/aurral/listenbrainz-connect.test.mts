import * as api from "./test-api.mts";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
const app = api.present(process.argv[2]);
const temp = await fs.mkdtemp(path.join(os.tmpdir(), "aurral-connect-"));
process.env["AURRAL_DATA_DIR"] = temp;
const { db } = await api.load(
  `${app}/backend/config/db-sqlite.ts`,
  api.database,
);
const { userOps } = await api.load(
  `${app}/backend/db/helpers/index.ts`,
  api.users,
);
const { hashPassword } = await api.load(
  `${app}/backend/middleware/passwordHash.ts`,
  api.password,
);
const { closeHonkerDb } = await api.load(
  `${app}/backend/services/honkerDb.ts`,
  api.honker,
);
const { resolveRequestUser } = await api.load(
  `${app}/backend/middleware/auth.ts`,
  api.authentication,
);
const history = await api.load(
  pathToFileURL(`${app}/backend/services/listeningHistory.ts`).href,
  api.listeningHistory,
);
const requirePackage = createRequire(`${app}/backend/package.json`);
const { Hono } = await api.load(
  pathToFileURL(requirePackage.resolve("hono")).href,
  api.honoModule,
);
const { default: scrobbling } = await api.load(
  pathToFileURL(`${app}/backend/routes/scrobbling.ts`).href,
  api.honoRoute,
);
const server = new Hono();
assert.ok(api.honoRouter(server));
server.use(
  async (
    c: { req: { raw: Request }; set: (key: string, value: unknown) => void },
    next: () => Promise<void>,
  ) => {
    c.set(
      "user",
      resolveRequestUser({ headers: Object.fromEntries(c.req.raw.headers) }),
    );
    await next();
  },
);
server.route("/api", scrobbling);
const localRequest = (url: string, options?: RequestInit): Promise<Response> =>
  Promise.resolve(server.request(url, options));
const base = "http://fixture.invalid";
try {
  const user = userOps.createUser(
    "listener",
    hashPassword("test-password"),
    "admin",
  );
  history.updateListenHistory(user.id, {
    listenbrainz: "original-listener",
    lastfm: "other-history",
  });
  assert.equal(
    history.getListenHistory(user.id).listenbrainz,
    "original-listener",
  );
  const headers = {
    Authorization:
      "Basic " + Buffer.from("listener:test-password").toString("base64"),
  };
  const realFetch = globalThis.fetch;
  let valid = false;
  let limited = true;
  const requests: { url: string; options: RequestInit; at: number }[] = [];
  const heldResponse = Promise.withResolvers<Response>();
  const heldStarted = Promise.withResolvers<void>();
  globalThis.fetch = async (url, options = {}) => {
    const requestUrl =
      url instanceof Request ? url.url : url instanceof URL ? url.href : url;
    if (requestUrl.startsWith("https://api.listenbrainz.org/")) {
      requests.push({ url: requestUrl, options, at: Date.now() });
      if (requestUrl.includes("/pending-fixture")) {
        heldStarted.resolve();
        return heldResponse.promise;
      }
      if (requestUrl.includes("/rate-limit-fixture") && limited) {
        limited = false;
        return new Response("{}", {
          status: 429,
          headers: { "X-RateLimit-Reset-In": "1" },
        });
      }
      return new Response(
        JSON.stringify(
          requestUrl.includes("validate-token")
            ? { valid, user_name: "verified-listener" }
            : { status: "ok" },
        ),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }
    return realFetch(url, options);
  };
  const link = async (payload: { token: string; expectedUsername?: string }) =>
    localRequest(base + "/api/scrobbling/listenbrainz/link", {
      method: "PUT",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  try {
    assert.equal(
      (await link({ token: "fixture-secret" })).status,
      400,
      "HTTP200 valid:false must reject token",
    );
    valid = true;
    assert.equal(
      (
        await link({
          token: "fixture-secret",
          expectedUsername: "wrong-account",
        })
      ).status,
      400,
      "identity mismatch must not save connection",
    );
    assert.equal(
      history.getListenHistory(user.id).listenbrainz,
      "original-listener",
      "rejected tokens must preserve the saved account",
    );
    const linked: unknown = await (
      await link({
        token: "fixture-secret",
        expectedUsername: "verified-listener",
      })
    ).json();
    assert.deepEqual(linked, {
      connected: true,
      displayName: "verified-listener",
    });
    assert.equal(
      history.getListenHistory(user.id).listenbrainz,
      "verified-listener",
    );
    assert.equal(
      history.getListenHistory(user.id).lastfm,
      "other-history",
      "other providers survive token alignment",
    );
    const status: unknown = await (
      await localRequest(base + "/api/scrobbling/status", { headers })
    ).json();
    assert.equal(
      api.record(api.record(status)["listenbrainz"])["connected"],
      true,
    );
    assert.ok(
      !JSON.stringify(status).includes("fixture-secret"),
      "public status must not disclose token",
    );
    const { listenbrainzSubmit, listenbrainzRequest } = await api.load(
      `${app}/backend/services/apiClients/listenbrainz.ts`,
      api.listenbrainz,
    );
    await listenbrainzSubmit({
      token: "fixture-secret",
      event: {
        playedAt: Date.now(),
        artist: "Fixture",
        title: "Fixture",
        albumMbid: "release-group",
        releaseMbid: "release",
      },
    });
    await listenbrainzRequest("/rate-limit-fixture");
    assert.equal(
      requests.filter((r) => r.url.includes("/rate-limit-fixture")).length,
      2,
      "429 read must retry after cooldown",
    );
    const held = listenbrainzRequest("/pending-fixture");
    let independenceTimer: ReturnType<typeof setTimeout> | undefined;
    try {
      await heldStarted.promise;
      const independent = await Promise.race([
        listenbrainzRequest("/independent-fixture"),
        new Promise((_, reject) => {
          independenceTimer = setTimeout(
            () =>
              reject(
                new Error("A pending response blocked an unrelated request"),
              ),
            5000,
          );
        }),
      ]);
      assert.deepEqual(independent, { status: "ok" });
    } finally {
      clearTimeout(independenceTimer);
      heldResponse.resolve(
        new Response(JSON.stringify({ status: "ok" }), {
          headers: { "Content-Type": "application/json" },
        }),
      );
      await held;
    }
    const submitted = requests.find((r) => r.url.includes("submit-listens"));
    assert.ok(submitted && typeof submitted.options.body === "string");
    const payload = api.array(
      api.record(JSON.parse(submitted.options.body))["payload"],
    );
    const info = api.record(
      api.record(api.record(payload[0])["track_metadata"])["additional_info"],
    );
    assert.equal(info["release_group_mbid"], "release-group");
    assert.equal(info["release_mbid"], "release");
    for (let i = 1; i < requests.length; i++) {
      const current = requests[i];
      const previous = requests[i - 1];
      assert.ok(current && previous);
      assert.ok(
        current.at - previous.at >= 990,
        "requests must be limited to one per second",
      );
    }
    assert.ok(
      requests.every((r) =>
        new Headers(r.options.headers).get("User-Agent")?.startsWith("Aurral/"),
      ),
    );
    await localRequest(base + "/api/scrobbling/listenbrainz/link", {
      method: "DELETE",
      headers,
    });
    assert.equal(
      history.getListenHistory(user.id).listenbrainz,
      "verified-listener",
      "unlink preserves public history",
    );
  } finally {
    globalThis.fetch = realFetch;
  }
  console.log(
    "PASS: saved history, verified token identity, safe status, throttling and MusicBrainz identifiers",
  );
} finally {
  closeHonkerDb();
  db.close();
  await fs.rm(temp, { recursive: true, force: true });
}
