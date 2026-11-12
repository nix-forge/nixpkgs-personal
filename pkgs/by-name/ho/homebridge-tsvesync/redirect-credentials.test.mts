import assert from "node:assert/strict";
import http, {
  type ClientRequest,
  type IncomingHttpHeaders,
  type RequestOptions,
} from "node:http";
import { createRequire } from "node:module";
import path from "node:path";
import { test } from "node:test";
import vm from "node:vm";

const packageRoot = process.argv[2];
if (!packageRoot)
  throw new Error("Pass the installed Homebridge VeSync package");
const require = createRequire(path.join(packageRoot, "package.json"));
const axiosRequire = createRequire(require.resolve("axios"));
const vesyncRequire = createRequire(require.resolve("tsvesync"));
assert.equal(vesyncRequire.resolve("axios"), require.resolve("axios"));
assert.equal(
  axiosRequire.resolve("follow-redirects"),
  require.resolve("follow-redirects"),
);
type Redirects = {
  http: {
    request: (
      options: RedirectOptions,
      callback: (response: http.IncomingMessage) => void,
    ) => ClientRequest;
  };
};
function isRedirects(value: unknown): value is Redirects {
  return (
    typeof value === "object" &&
    value !== null &&
    "http" in value &&
    typeof value.http === "object" &&
    value.http !== null &&
    "request" in value.http &&
    typeof value.http.request === "function"
  );
}
function loadRedirects(value: unknown): Redirects {
  assert.ok(isRedirects(value), "Expected the installed redirect client");
  return value;
}
const redirects = loadRedirects(require("follow-redirects"));

type Headers = Record<string, string | string[]> | string[];
type RedirectOptions = Omit<RequestOptions, "headers"> & {
  headers: Headers;
  sensitiveHeaders?: string[];
  maxRedirects: number;
};
type CapturedRequest = {
  headers: IncomingHttpHeaders;
  method: string;
  body: string;
};

function isStringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) &&
    value.every((item: unknown) => typeof item === "string")
  );
}
function isHeaders(value: unknown): value is IncomingHttpHeaders {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.values(value).every(
      (item: unknown) => typeof item === "string" || isStringArray(item),
    )
  );
}
function isCapturedRequest(value: unknown): value is CapturedRequest {
  return (
    typeof value === "object" &&
    value !== null &&
    "headers" in value &&
    isHeaders(value.headers) &&
    "method" in value &&
    typeof value.method === "string" &&
    "body" in value &&
    typeof value.body === "string"
  );
}
type Axios = {
  get: (
    url: string,
    options: {
      proxy: false;
      timeout: number;
      headers: Record<string, string>;
    },
  ) => Promise<{ data: CapturedRequest }>;
};
function isAxios(value: unknown): value is Axios {
  return (
    (typeof value === "function" ||
      (typeof value === "object" && value !== null)) &&
    "get" in value &&
    typeof value.get === "function"
  );
}

async function capture(
  request: http.IncomingMessage,
): Promise<CapturedRequest> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    assert.ok(Buffer.isBuffer(chunk));
    chunks.push(chunk);
  }
  return {
    headers: request.headers,
    method: request.method ?? "",
    body: Buffer.concat(chunks).toString(),
  };
}

const initialRequests: CapturedRequest[] = [];
const target = http.createServer((request, response) => {
  void capture(request).then(
    (value) => response.end(JSON.stringify(value)),
    () => response.destroy(),
  );
});
await new Promise<void>((resolve) => target.listen(0, "127.0.0.1", resolve));
const targetAddress = target.address();
assert.ok(targetAddress && typeof targetAddress !== "string");
const targetUrl = `http://127.0.0.1:${targetAddress.port}`;
const origin = http.createServer((request, response) => {
  void capture(request).then(
    (value) => {
      if (request.url === "/capture") {
        response.end(JSON.stringify(value));
        return;
      }
      initialRequests.push(value);
      response.writeHead(302, {
        Location:
          request.url === "/same"
            ? "/capture"
            : request.url === "/loop"
              ? "/loop"
              : targetUrl,
      });
      response.end();
    },
    () => response.destroy(),
  );
});
await new Promise<void>((resolve) => origin.listen(0, "127.0.0.1", resolve));
const originAddress = origin.address();
assert.ok(originAddress && typeof originAddress !== "string");
const originPort = originAddress.port;
const originUrl = `http://127.0.0.1:${originPort}`;

function redirectRequest(
  headers: Headers,
  sensitiveHeaders?: string[],
  requestPath = "/cross",
  method = "GET",
  body = "",
  maxRedirects = 3,
): Promise<CapturedRequest> {
  let deadline: ReturnType<typeof setTimeout> | undefined;
  return new Promise<CapturedRequest>((resolve, reject) => {
    const options: RedirectOptions = {
      hostname: "127.0.0.1",
      port: originPort,
      path: requestPath,
      headers,
      method,
      maxRedirects,
      ...(sensitiveHeaders === undefined ? {} : { sensitiveHeaders }),
    };
    const outgoing = redirects.http.request(options, (response) => {
      response.on("error", reject);
      void capture(response).then((value) => {
        try {
          const parsed: unknown = JSON.parse(value.body);
          assert.ok(isCapturedRequest(parsed));
          resolve(parsed);
        } catch (error) {
          reject(error);
        }
      }, reject);
    });
    deadline = setTimeout(
      () => outgoing.destroy(new Error("Loopback redirect deadline exceeded")),
      5000,
    );
    outgoing.on("error", reject);
    outgoing.end(body);
  }).finally(() => clearTimeout(deadline));
}

const credentials = {
  Authorization: "sentinel-authorization",
  "Proxy-Authorization": "sentinel-proxy",
  Cookie: "sentinel-cookie",
  "X-Api^Key": "sentinel-caret",
  "x-ToKen|Secret": "sentinel-pipe",
  "X-Private": "sentinel-private",
};
const customNames = ["x-api^key", "X-TOKEN|SECRET", "x-private"];
const ordinary = { "X-Keep": "ordinary", "X-Second": "second" };
function flatHeaders(headers: Record<string, string>): string[] {
  return Object.entries({
    Host: `127.0.0.1:${originPort}`,
    ...headers,
  }).flat();
}
function assertCredentials(
  headers: IncomingHttpHeaders,
  present: boolean,
): void {
  for (const [name, value] of Object.entries(credentials)) {
    assert.equal(
      headers[name.toLowerCase()],
      present ? value : undefined,
      name,
    );
  }
}
function assertOrdinary(headers: IncomingHttpHeaders): void {
  assert.equal(headers["x-keep"], "ordinary");
  assert.equal(headers["x-second"], "second");
}
function foreignNames(): string[] {
  const names: unknown = vm.runInNewContext(
    '["x-api^key", "X-TOKEN|SECRET", "x-private"]',
  );
  assert.ok(isStringArray(names));
  assert.notEqual(Object.getPrototypeOf(names), Array.prototype);
  return names;
}

try {
  await test("object custom-sensitive names are matched literally and case-insensitively", async () => {
    const result = await redirectRequest(
      { ...credentials, ...ordinary, "X-Multi": ["one", "two"] },
      customNames,
    );
    const initial = initialRequests.at(-1);
    assert.ok(initial);
    assertCredentials(initial.headers, true);
    assertCredentials(result.headers, false);
    assertOrdinary(result.headers);
    assert.equal(result.headers["x-multi"], "one, two");
    assert.equal(result.headers.host, `127.0.0.1:${targetAddress.port}`);
  });
  await test("flat alternating header arrays strip built-in and custom credentials", async () => {
    const result = await redirectRequest(
      flatHeaders({ ...credentials, ...ordinary }),
      customNames,
    );
    const initial = initialRequests.at(-1);
    assert.ok(initial);
    assertCredentials(initial.headers, true);
    assertCredentials(result.headers, false);
    assertOrdinary(result.headers);
  });
  for (const flat of [false, true]) {
    await test(`cross-realm sensitive names work with ${flat ? "flat arrays" : "objects"}`, async () => {
      const headers = { ...credentials, ...ordinary };
      const result = await redirectRequest(
        flat ? flatHeaders(headers) : headers,
        foreignNames(),
      );
      assert.equal(result.headers["x-private"], undefined);
      assertCredentials(result.headers, false);
      assertOrdinary(result.headers);
    });
  }
  for (const flat of [false, true]) {
    await test(`same-origin redirects preserve ${flat ? "flat-array" : "object"} credentials`, async () => {
      const headers = { ...credentials, ...ordinary };
      const result = await redirectRequest(
        flat ? flatHeaders(headers) : headers,
        foreignNames(),
        "/same",
      );
      assertCredentials(result.headers, true);
      assertOrdinary(result.headers);
    });
  }
  await test("POST302 drops body/content headers and replaces a flat-array Host", async () => {
    const result = await redirectRequest(
      flatHeaders({
        ...ordinary,
        "Content-Type": "text/plain",
        "Content-Length": "4",
      }),
      undefined,
      "/cross",
      "POST",
      "body",
    );
    const initial = initialRequests.at(-1);
    assert.ok(initial);
    assert.equal(initial.method, "POST");
    assert.equal(initial.body, "body");
    assert.equal(result.method, "GET");
    assert.equal(result.body, "");
    assert.equal(result.headers["content-type"], undefined);
    assert.equal(result.headers["content-length"], undefined);
    assert.equal(result.headers.host, `127.0.0.1:${targetAddress.port}`);
    assertOrdinary(result.headers);
  });
  await test("redirect-limit errors retain their public code", async () => {
    await assert.rejects(
      redirectRequest({}, undefined, "/loop", "GET", "", 1),
      {
        code: "ERR_FR_TOO_MANY_REDIRECTS",
      },
    );
  });
  await test("installed Axios keeps normal requests and redirects working", async () => {
    const axios: unknown = require("axios");
    assert.ok(isAxios(axios), "Expected the installed Axios client");
    const headers = { Authorization: credentials.Authorization, ...ordinary };
    const same = await axios.get(originUrl + "/same", {
      proxy: false,
      timeout: 5000,
      headers,
    });
    assert.equal(same.data.headers.authorization, credentials.Authorization);
    assertOrdinary(same.data.headers);
    const cross = await axios.get(originUrl + "/cross", {
      proxy: false,
      timeout: 5000,
      headers,
    });
    assert.equal(cross.data.headers.authorization, undefined);
    assertOrdinary(cross.data.headers);
  });
} finally {
  origin.closeAllConnections();
  target.closeAllConnections();
  await Promise.all(
    [origin, target].map(
      (server) =>
        new Promise<void>((resolve, reject) => {
          server.close((error) => (error ? reject(error) : resolve()));
        }),
    ),
  );
}
