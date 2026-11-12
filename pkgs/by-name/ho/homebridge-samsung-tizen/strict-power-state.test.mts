import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { readFileSync } from "node:fs";
import { createRequire, stripTypeScriptTypes } from "node:module";
import path from "node:path";
import vm from "node:vm";
import {
  checkActualFrameConsumers,
  checkInflightDestroy,
} from "./scripts/actual-consumer-check.mts";
import type * as Maintained from "./scripts/strict-power.mts";

function packageRoot(): string {
  const root = process.argv[2];
  assert.ok(root, "Expected actual upstream package directory");
  return root;
}
const root = packageRoot();
const sourceOnly = process.argv.includes("--source-only");
function program(name: string): string {
  return readFileSync(
    path.join(
      root,
      sourceOnly ? `src/device/${name}.ts` : `dist/device/${name}.js`,
    ),
    "utf8",
  );
}
const strict = new vm.SourceTextModule(
  sourceOnly
    ? stripTypeScriptTypes(program("strict-power"))
    : program("strict-power"),
);
await strict.link(async (id) => {
  assert.equal(id, "node:timers/promises");
  const { setTimeout } = await import("node:timers/promises");
  return new vm.SyntheticModule(["setTimeout"], function () {
    this.setExport("setTimeout", setTimeout);
  });
});
await strict.evaluate();
// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- exercise the installed module with its maintained source contract.
const strictApi = strict.namespace as typeof Maintained;
const { observeStrictPower, StrictPowerCommands, UnsupportedStrictPowerError } =
  strictApi;
interface XmlParser {
  parse(xml: string, validate: boolean): unknown;
}
const parserRoot = sourceOnly ? process.argv[4] : root;
assert.ok(
  parserRoot,
  "Source-only checks require the actual pinned XML parser dependency",
);
// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- dependency selected by the actual package's lockfile.
const { XMLParser } = createRequire(path.join(parserRoot, "package.json"))(
  "fast-xml-parser",
) as { XMLParser: new (options: Record<string, unknown>) => XmlParser };
const parseXml = (xml: string): unknown =>
  new XMLParser({
    ignoreAttributes: false,
    parseTagValue: false,
    processEntities: false,
  }).parse(xml, true);
const signal = AbortSignal.timeout(5000);
const urn = "urn:schemas-upnp-org:service:RenderingControl:1";
function requestUrl(input: Parameters<typeof fetch>[0]): string {
  if (typeof input === "string") return input;
  return input instanceof URL ? input.href : input.url;
}
function network(
  state: string | undefined,
  active: boolean | "fault",
  frame = false,
): typeof fetch {
  return async (url, options) => {
    if (requestUrl(url).endsWith("/api/v2/"))
      return Response.json({
        device: { PowerState: state, FrameTVSupport: frame ? "true" : "false" },
      });
    assert.equal(options?.method, "POST");
    if (active === false)
      throw Object.assign(new Error("refused"), {
        cause: { code: "ECONNREFUSED" },
      });
    return new Response(
      active === "fault"
        ? "<Fault/>"
        : `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:GetVolumeResponse xmlns:u="${urn}"><CurrentVolume>20</CurrentVolume></u:GetVolumeResponse></s:Body></s:Envelope>`,
    );
  };
}
assert.equal(
  await observeStrictPower("192.0.2.1", signal, network("on", true), parseXml),
  true,
);
for (const standby of ["", "standby", "off"])
  assert.equal(
    await observeStrictPower(
      "192.0.2.1",
      signal,
      network(standby, false),
      parseXml,
    ),
    false,
  );
for (const [state, active] of [
  [undefined, true],
  ["on", false],
  ["off", true],
  ["on", "fault"],
] as const) {
  await assert.rejects(
    observeStrictPower("192.0.2.1", signal, network(state, active), parseXml),
  );
}
await assert.rejects(
  observeStrictPower("192.0.2.1", signal, network("on", true, true), parseXml),
  UnsupportedStrictPowerError,
);
await assert.rejects(
  observeStrictPower(
    "192.0.2.1",
    signal,
    async () => {
      throw new Error("timeout");
    },
    parseXml,
  ),
);

for (const xml of [
  `NOT XML ${urn} <GetVolumeResponse><CurrentVolume>20</CurrentVolume></GetVolumeResponse>`,
  `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><!-- <GetVolumeResponse xmlns="${urn}"><CurrentVolume>20</CurrentVolume></GetVolumeResponse> --></s:Body></s:Envelope>`,
  `<s:Envelope xmlns:s="wrong"><s:Body><u:GetVolumeResponse xmlns:u="${urn}"><CurrentVolume>20</CurrentVolume></u:GetVolumeResponse></s:Body></s:Envelope>`,
  `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:GetVolumeResponse xmlns:u="wrong"><CurrentVolume>20</CurrentVolume></u:GetVolumeResponse></s:Body></s:Envelope>`,
  `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:GetVolumeResponse xmlns:u="${urn}"><CurrentVolume>20</CurrentVolume></u:GetVolumeResponse></s:Envelope>`,
]) {
  await assert.rejects(
    observeStrictPower(
      "192.0.2.1",
      signal,
      async (url) =>
        requestUrl(url).endsWith("/api/v2/")
          ? Response.json({ device: { PowerState: "on" } })
          : new Response(xml),
      parseXml,
    ),
  );
}

function fixture(initial: boolean | undefined, confirm = true) {
  let state = initial;
  let now = 0;
  const sends: Array<{ value: boolean; observed: boolean | undefined }> = [];
  const confirmations: boolean[] = [];
  const commands = new StrictPowerCommands(
    {
      observe: async () => {
        if (state === undefined) throw new Error("unknown");
        return state;
      },
      send: async (value, observed) => {
        sends.push({ value, observed });
        if (confirm) state = value;
      },
      confirmed: (value) => {
        confirmations.push(value);
      },
    },
    () => now,
    async (ms, waitSignal) => {
      waitSignal.throwIfAborted();
      now += ms;
    },
  );
  return {
    commands,
    sends,
    confirmations,
    state: (value: boolean | undefined) => {
      state = value;
    },
  };
}
for (const value of [false, true]) {
  const f = fixture(value);
  await f.commands.set(value);
  assert.equal(
    f.sends.length,
    0,
    "Already-confirmed states require no command",
  );
}
const unknownOff = fixture(undefined);
await assert.rejects(unknownOff.commands.set(false), /unknown/);
assert.equal(unknownOff.sends.length, 0, "Unknown Off must never toggle");
unknownOff.state(true);
await unknownOff.commands.set(false);
assert.equal(
  unknownOff.sends.length,
  1,
  "A failed preflight must not latch a nonexistent command",
);
const unknownOn = fixture(undefined);
await unknownOn.commands.set(true);
assert.deepEqual(
  unknownOn.sends,
  [{ value: true, observed: undefined }],
  "Unknown On delegates only the guarded WOL path",
);
const concurrent = fixture(true);
await Promise.all([
  concurrent.commands.set(false),
  concurrent.commands.set(false),
]);
assert.equal(
  concurrent.sends.length,
  1,
  "Serialized Off requests must send one command",
);
const ordered = fixture(false);
await Promise.all([ordered.commands.set(true), ordered.commands.set(false)]);
assert.deepEqual(
  ordered.sends.map((command) => command.value),
  [true, false],
);
const unconfirmed = fixture(true, false);
await assert.rejects(unconfirmed.commands.set(false), /not confirmed/);
await assert.rejects(unconfirmed.commands.set(false), /not confirmed/);
assert.equal(
  unconfirmed.sends.length,
  1,
  "An unconfirmed command must prevent duplicate toggles",
);
unconfirmed.commands.destroy();
await assert.rejects(unconfirmed.commands.observe(), /destroyed/);

// Scale only the actual confirmation deadline, retaining the real abort/timer API.
const deadlineContext = vm.createContext({
  AbortController,
  AbortSignal: {
    timeout: (ms: number) => AbortSignal.timeout(ms === 15000 ? 20 : ms),
    any: (signals: AbortSignal[]) => AbortSignal.any(signals),
  },
  performance,
});
const deadlineModule = new vm.SourceTextModule(
  sourceOnly
    ? stripTypeScriptTypes(program("strict-power"))
    : program("strict-power"),
  { context: deadlineContext },
);
await deadlineModule.link(async (id) => {
  assert.equal(id, "node:timers/promises");
  const { setTimeout } = await import("node:timers/promises");
  return new vm.SyntheticModule(
    ["setTimeout"],
    function () {
      this.setExport("setTimeout", setTimeout);
    },
    { context: deadlineContext },
  );
});
await deadlineModule.evaluate();
// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- same actual class contract in a controlled deadline context.
const DeadlineCommands = (deadlineModule.namespace as typeof Maintained)
  .StrictPowerCommands;
let deadlineSends = 0;
const deadlineCommands = new DeadlineCommands(
  {
    observe: async (querySignal) => {
      querySignal.throwIfAborted();
      return true;
    },
    send: async () => {
      deadlineSends++;
    },
    confirmed: () => {},
  },
  () => 0,
);
const { setTimeout: pause } = await import("node:timers/promises");
// A backwards/frozen clock must not keep an expired network confirmation alive.
await assert.rejects(
  Promise.race([
    deadlineCommands.set(false),
    pause(200).then(() => {
      throw new Error("confirmation exceeded deadline");
    }),
  ]),
  (error: unknown) =>
    error instanceof Error && !error.message.includes("exceeded deadline"),
);
await assert.rejects(deadlineCommands.set(false));
assert.equal(
  deadlineSends,
  1,
  "Timeout must preserve the unconfirmed command latch",
);
await checkActualFrameConsumers(root, sourceOnly, {
  observeStrictPower,
  StrictPowerCommands,
  UnsupportedStrictPowerError,
});
await checkInflightDestroy({
  observeStrictPower,
  StrictPowerCommands,
  UnsupportedStrictPowerError,
});

// Execute the actual upstream event router. An SSDP/UPnP event is not panel evidence.
function debounce<T extends (...args: never[]) => unknown>(
  fn: T,
): T & { immediate: T } {
  return Object.assign(fn, { immediate: fn });
}
const context = vm.createContext({
  Date,
  setInterval: () => 0,
  setTimeout: () => 0,
  clearTimeout,
});
const power = new vm.SourceTextModule(
  sourceOnly
    ? stripTypeScriptTypes(program("power"), { mode: "transform" })
    : program("power"),
  {
    context,
  },
);
const mocks: Record<string, Record<string, unknown>> = {
  "../lib/tools.js": {
    debounce,
    retry: async (fn: () => Promise<unknown>) => fn(),
    sleep: async () => {},
  },
  "../types/index.js": {
    TizenDeviceInfo: undefined,
    SsdpEvent: { ALIVE: "ssdp:alive", BYEBYE: "ssdp:byebye" },
    FrameEvent: { STANDBY: "standby", WAKEUP: "wakeup" },
  },
  "./device.js": {
    Device: function Device() {
      // Constructor identity only; the event-router fixture supplies its own device.
    },
  },
};
await power.link(async (id) => {
  const exports = mocks[id];
  assert.ok(exports, `Unexpected upstream import ${id}`);
  return new vm.SyntheticModule(
    Object.keys(exports),
    function () {
      for (const [key, value] of Object.entries(exports))
        this.setExport(key, value);
    },
    { context },
  );
});
await power.evaluate();
interface Monitor {
  withPowerLatch(value: boolean, send: () => Promise<void>): Promise<void>;
}
// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- bounded actual upstream constructor interface.
const { PowerMonitor } = power.namespace as {
  PowerMonitor: new (device: unknown, probe: unknown) => Monitor;
};
const device = Object.assign(new EventEmitter(), {
  power: false,
  storage: { powerStateSupport: false },
  hasOption: (key: string) => key === "PowerState.Strict",
  log: { debug: () => {} },
});
let observations = 0;
const monitor = new PowerMonitor(device, {
  ping: async () => true,
  getInfo: async () => ({}),
  getPowerState: async () => {
    observations++;
    throw new Error("unknown");
  },
});
for (const [event, value] of [
  ["ssdp:update", "ssdp:alive"],
  ["frame:power", "wakeup"],
  ["upnp:update", undefined],
])
  device.emit(event!, value);
await Promise.resolve();
await Promise.resolve();
assert.equal(observations, 3);
assert.equal(
  device.power,
  false,
  "Uncorroborated reachability and wake events must not report On",
);
await assert.rejects(
  monitor.withPowerLatch(true, async () => {}),
  /verified/,
);
console.log(
  "Actual Samsung strict observation, serialized command, and event routing checks passed",
);
