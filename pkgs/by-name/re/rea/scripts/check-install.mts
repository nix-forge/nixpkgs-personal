import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { once } from "node:events";
import {
  mkdtemp,
  readFile,
  readdir,
  realpath,
  rm,
  writeFile,
} from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const isArray = (value: unknown): value is unknown[] => Array.isArray(value);
interface FridaManager {
  listDevices(): Promise<unknown>;
  availabilityFailure(): unknown;
  closeAll(): Promise<void>;
}
const isFridaManagerFactory = (
  value: unknown,
): value is new () => FridaManager => typeof value === "function";

interface Pty {
  kill(): void;
  onData(callback: (data: string) => void): void;
  onExit(callback: (event: { exitCode: number }) => void): void;
}
interface PtyFactory {
  spawn(
    file: string,
    args: string[],
    options: Record<string, unknown>,
  ): unknown;
}
const isPtyFactory = (value: unknown): value is PtyFactory =>
  isRecord(value) && typeof value["spawn"] === "function";
const isPty = (value: unknown): value is Pty =>
  isRecord(value) &&
  typeof value["kill"] === "function" &&
  typeof value["onData"] === "function" &&
  typeof value["onExit"] === "function";

const [output, skillsOutput, version, shell] = process.argv.slice(2);
assert(output && skillsOutput && version && shell);
const root = join(output, "lib/node_modules/rea-agents");
const require = createRequire(join(root, "package.json"));
const temporary = await mkdtemp(join(tmpdir(), "rea-install-check-"));
const environment = {
  ...process.env,
  HOME: temporary,
  XDG_CONFIG_HOME: join(temporary, "config"),
  XDG_CACHE_HOME: join(temporary, "cache"),
  CODEX_HOME: join(temporary, "codex"),
};
const cli = (name: string, args: string[]) =>
  execFileSync(join(output, "bin", name), args, {
    cwd: temporary,
    env: environment,
    encoding: "utf8",
    timeout: 60_000,
    maxBuffer: 16 * 1024 * 1024,
  });

try {
  for (const name of ["rea", "rea-agents"]) {
    assert(cli(name, ["--version"]).includes(version));
    assert(cli(name, ["--help"]).includes("analyze-javascript-application"));
  }
  const skillRoot = join(
    skillsOutput,
    "share/agent-skills/reverse-engineer-anything",
  );
  assert.equal(
    await realpath(join(root, "skills/reverse-engineer-anything")),
    skillRoot,
  );
  const skill = await readFile(join(skillRoot, "SKILL.md"), "utf8");
  assert.match(skill, /^name: reverse-engineer-anything$/m);
  assert.match(
    skill,
    new RegExp(`rea-agents@${version.replaceAll(".", "\\.")}`),
  );
  assert(!skill.includes("rea-agents@latest"));
  await Promise.all(
    [...skill.matchAll(/\]\((references\/[^)#]+)(?:#[^)]*)?\)/g)].map(
      async (match) => {
        assert(match[1]);
        assert((await readFile(join(skillRoot, match[1]), "utf8")).length > 0);
      },
    ),
  );
  assert((await readdir(join(skillRoot, "references"))).length > 0);
  assert(
    (
      await readFile(join(skillsOutput, "share/licenses/rea/LICENSE"), "utf8")
    ).includes("MIT"),
  );
  await Promise.all(
    [
      join(output, "share/licenses/rea-node-pty/LICENSE"),
      join(output, "share/licenses/node-addon-api/LICENSE.md"),
      join(root, "third_party/evmole/LICENSE"),
    ].map(async (license) => {
      assert((await readFile(license, "utf8")).includes("MIT"));
    }),
  );

  // The optional native Frida provider is deliberately absent. Verify upstream
  // reports an unavailable capability without breaking the CLI or other engines.
  assert.throws(() => require.resolve("frida"), { code: "MODULE_NOT_FOUND" });
  const fridaModule: unknown = await import(
    pathToFileURL(join(root, "dist/frida/FridaInstrumentationManager.js")).href
  );
  assert(isRecord(fridaModule));
  const FridaManager = fridaModule["FridaInstrumentationManager"];
  assert(isFridaManagerFactory(FridaManager));
  const frida = new FridaManager();
  try {
    const unavailable = await frida.listDevices();
    assert(isRecord(unavailable));
    assert.equal(unavailable["ok"], false);
    assert(isRecord(unavailable["error"]));
    assert.equal(
      unavailable["error"]["_tag"],
      "AnalysisCapabilityUnavailableError",
    );
    const failure = frida.availabilityFailure();
    assert(isRecord(failure));
    assert.equal(failure["providerId"], "frida");
  } finally {
    await frida.closeAll();
  }

  // Exercise the source-built Node-API addon, including Darwin's spawn helper.
  const factory: unknown = require("@lydell/node-pty");
  assert(isPtyFactory(factory));
  const pty = factory.spawn(shell, ["-c", "printf rea-pty-ok"], {
    cwd: temporary,
    env: environment,
    name: "xterm",
    cols: 80,
    rows: 24,
  });
  assert(isPty(pty));
  let captured = "";
  pty.onData((data) => {
    captured += data;
  });
  await new Promise<void>((resolve, reject) => {
    const deadline = setTimeout(() => {
      pty.kill();
      reject(new Error("PTY timed out"));
    }, 10_000);
    pty.onExit(({ exitCode }) => {
      clearTimeout(deadline);
      try {
        assert.equal(exitCode, 0);
        assert(captured.includes("rea-pty-ok"));
        resolve();
      } catch (error) {
        reject(error);
      }
    });
  });

  // The built-in JavaScript path must work without optional analysis engines.
  await writeFile(
    join(temporary, "package.json"),
    JSON.stringify({
      name: "rea-nix-fixture",
      version: "1.0.0",
      main: "index.js",
    }),
  );
  await writeFile(
    join(temporary, "index.js"),
    "module.exports = () => 'rea-static-fixture';\n",
  );
  // Darwin's Nix sandbox withholds the process visibility needed for worker
  // ownership. Run this same check outside the sandbox on Darwin as well.
  if (!(process.platform === "darwin" && process.argv.includes("--sandbox"))) {
    const analysis: unknown = JSON.parse(
      cli("rea", ["analyze-javascript-application", temporary, "--json"]),
    );
    assert(analysis && typeof analysis === "object");
    assert(JSON.stringify(analysis).includes("index.js"));
  }
  const preview: unknown = JSON.parse(
    cli("rea", ["setup", "--client", "codex", "--dry-run", "--json"]),
  );
  assert(JSON.stringify(preview).includes("reverse-engineer-anything"));
  // Setup preview may inspect paths but must not create a user's configuration.
  assert(!(await readdir(temporary)).includes("codex"));

  const server = spawn(join(output, "bin/rea"), ["mcp"], {
    cwd: temporary,
    env: environment,
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stderr = "";
  server.stderr.setEncoding("utf8").on("data", (data) => {
    stderr += data;
  });
  const lines = createInterface({ input: server.stdout });
  const pending = new Map<
    number,
    { resolve: (result: unknown) => void; reject: (error: unknown) => void }
  >();
  let nextId = 0;
  const rejectPending = (error: unknown) => {
    for (const item of pending.values()) item.reject(error);
    pending.clear();
  };
  lines.on("line", (line) => {
    try {
      const message: unknown = JSON.parse(line);
      assert(isRecord(message));
      if (message["id"] === undefined) return;
      assert(typeof message["id"] === "number");
      const item = pending.get(message["id"]);
      if (item) {
        pending.delete(message["id"]);
        if (message["error"])
          item.reject(new Error(JSON.stringify(message["error"])));
        else item.resolve(message["result"]);
      }
    } catch (error) {
      rejectPending(error);
    }
  });
  server.on("error", rejectPending);
  server.on("exit", (code) =>
    rejectPending(new Error(`MCP exited ${code}: ${stderr}`)),
  );
  const deadline = setTimeout(() => {
    rejectPending(new Error(`MCP timed out: ${stderr}`));
    server.kill("SIGKILL");
  }, 30_000);
  const send = (message: Record<string, unknown>) =>
    server.stdin.write(JSON.stringify({ jsonrpc: "2.0", ...message }) + "\n");
  const request = (method: string, params: Record<string, unknown> = {}) =>
    new Promise<unknown>((resolve, reject) => {
      const id = ++nextId;
      pending.set(id, { resolve, reject });
      send({ id, method, params });
    });
  try {
    const initialized = await request("initialize", {
      protocolVersion: "2025-11-25",
      capabilities: {},
      clientInfo: { name: "rea-nix-check", version: "1.0.0" },
    });
    assert(isRecord(initialized));
    assert(isRecord(initialized["serverInfo"]));
    assert.equal(initialized["serverInfo"]["version"], version);
    send({ method: "notifications/initialized" });
    const tools: { name: string }[] = [];
    let cursor: string | undefined;
    do {
      // MCP pagination is sequential because each response supplies the next cursor.
      const page = await request("tools/list", cursor ? { cursor } : {});
      assert(isRecord(page));
      assert(isArray(page["tools"]));
      for (const tool of page["tools"]) {
        assert(isRecord(tool));
        assert(typeof tool["name"] === "string");
        tools.push({ name: tool["name"] });
      }
      assert(
        page["nextCursor"] === undefined ||
          typeof page["nextCursor"] === "string",
      );
      cursor = page["nextCursor"];
    } while (cursor);
    assert(
      tools.some((tool) => tool["name"] === "analyze_javascript_application"),
    );
    assert.equal(
      tools.length,
      Number(skill.match(/^  tool_count: (\d+)$/m)?.[1]),
    );
  } finally {
    if (server.pid && server.exitCode === null && server.signalCode === null) {
      const exited = once(server, "exit");
      server.stdin.end();
      await exited;
    }
    clearTimeout(deadline);
    lines.close();
  }
  console.log("CLI, MCP, PTY, skills and setup preview passed");
} finally {
  await rm(temporary, { recursive: true, force: true });
}
