/** Whole-module Samsung consumer checks; injected mocks never contact a TV.
 * Invoke from the existing test after strict.evaluate():
 *   await checkActualFrameConsumers(root, sourceOnly, { observeStrictPower, StrictPowerCommands, UnsupportedStrictPowerError });
 *   await checkInflightDestroy({ observeStrictPower, StrictPowerCommands, UnsupportedStrictPowerError });
 * Fixture wire commands remain serial so their order is part of each assertion.
 * The typed and untyped lint boundaries both permit these necessary serial awaits.
 * Raw 6 legacy control:
 *   await checkActualFrameConsumers(rawRoot, true, undefined, { legacyOnly: true });
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import path from "node:path";
import vm from "node:vm";

const controllerSamsungPlatform = function SamsungPlatform() {
  // Import identity only; this fixture supplies the exercised instance.
};
const protocolUpnpClient = function UPnPClient() {
  // Import identity only; this fixture supplies the exercised instance.
};
const controllerDevice = function Device() {
  // Import identity only; this fixture supplies the exercised instance.
};
const homebridgePlatformAccessory = function PlatformAccessory() {
  // Import identity only; this fixture supplies the exercised instance.
};
const televisionDevice = function Device() {
  // Import identity only; this fixture supplies the exercised instance.
};
const televisionSamsungPlatform = function SamsungPlatform() {
  // Import identity only; this fixture supplies the exercised instance.
};
const informationService = function InformationService() {
  // Import identity only; this fixture supplies the exercised instance.
};
const inputService = function InputService() {
  // Import identity only; this fixture supplies the exercised instance.
};
const speakerService = function SpeakerService() {
  // Import identity only; this fixture supplies the exercised instance.
};
const televisionService = function TelevisionService() {
  // Import identity only; this fixture supplies the exercised instance.
};
const volumeService = function VolumeService() {
  // Import identity only; this fixture supplies the exercised instance.
};

function observationNotInitialized(): never {
  throw new Error("Observation rendezvous not initialized");
}

type MockExports = Record<string, unknown>;
type WireCommand =
  ["key", string] | ["hold", string, number] | ["art", boolean] | ["wol"];
type ConsumerCall = ["guarded-power" | "art-mode", boolean];
interface FixtureDevice {
  isFrame: boolean;
  power: boolean;
  config: { ip: string; mac: string };
  cache: { flush(): void };
  hasOption(option: string): boolean;
  setPower(value: boolean): Promise<void>;
  setArtMode(value: boolean): Promise<void>;
}
interface Controller {
  powerOn(): Promise<void>;
  powerOff(): Promise<void>;
  setArtMode(value: boolean): Promise<void>;
  destroy(): void;
}
interface StrictAdapter {
  observe(signal: AbortSignal): Promise<boolean>;
  send(value: boolean, observed: boolean | undefined): Promise<void>;
  confirmed(value: boolean): void;
}
interface StrictCommands {
  set(value: boolean): Promise<void>;
  observe(signal?: AbortSignal): Promise<boolean>;
  destroy(): void;
}
export interface StrictConsumerModule {
  observeStrictPower(
    ip: string,
    signal: AbortSignal,
    request: typeof fetch,
    parseXml: (xml: string) => unknown,
  ): Promise<boolean>;
  UnsupportedStrictPowerError: new (message?: string) => Error;
  StrictPowerCommands: new (adapter: StrictAdapter) => StrictCommands;
}
interface ControllerModule {
  DeviceController: new (
    device: FixtureDevice,
    platform: MockExports,
  ) => Controller;
}
interface TelevisionModule {
  TelevisionAccessory: {
    prototype: {
      setMain(this: { device: FixtureDevice }, value: boolean): Promise<void>;
    };
  };
}

async function loadActual(
  root: string,
  relative: string,
  sourceOnly: boolean,
  mocks: Record<string, MockExports>,
): Promise<unknown> {
  const filename = path.join(
    root,
    sourceOnly ? `src/${relative}.ts` : `dist/${relative}.js`,
  );
  const source = readFileSync(filename, "utf8");
  const module = new vm.SourceTextModule(
    sourceOnly ? stripTypeScriptTypes(source, { mode: "transform" }) : source,
  );
  await module.link(async (specifier) => {
    assert.ok(
      Object.hasOwn(mocks, specifier),
      `Unexpected actual consumer import ${specifier}`,
    );
    const values = mocks[specifier];
    assert.ok(values);
    return new vm.SyntheticModule(Object.keys(values), function () {
      for (const [key, value] of Object.entries(values))
        this.setExport(key, value);
    });
  });
  await module.evaluate();
  return module.namespace;
}

export async function checkActualFrameConsumers(
  root: string,
  sourceOnly: boolean,
  strict: StrictConsumerModule | undefined,
  { legacyOnly = false }: { legacyOnly?: boolean } = {},
): Promise<void> {
  const commands: WireCommand[] = [];
  class Socket {
    async click(key: string): Promise<void> {
      commands.push(["key", key]);
    }
    async hold(key: string, ms: number): Promise<void> {
      commands.push(["hold", key, ms]);
    }
    start() {}
    destroy() {}
  }
  class FrameSocket {
    async setArtMode(value: boolean): Promise<void> {
      commands.push(["art", value]);
    }
    destroy() {}
  }
  class SmartThingsClient {
    isAvailable = false;
  }
  class PowerMonitor {
    isPowering = false;
    async settled() {}
    async withPowerLatch(
      _value: boolean,
      send: () => Promise<void>,
    ): Promise<void> {
      await send();
    }
  }
  const controllerModule = await loadActual(
    root,
    "device/controller",
    sourceOnly,
    {
      "../errors.js": {
        IgnorableError: class extends Error {},
        TvAlreadyOffError: class extends Error {},
        TvAlreadyOnError: class extends Error {},
        TvOfflineError: class extends Error {},
        TvPoweringError: class extends Error {},
      },
      "../lib/http.js": {
        request: async () => {
          throw new Error("Unexpected HTTP path");
        },
      },
      "fast-xml-parser": {
        XMLParser: class {
          parse() {
            throw new Error("Frame-control fixture must not parse HTTP");
          }
        },
      },
      "../lib/parsers.js": {
        parseCommands: () => {
          throw new Error("Unexpected raw command path");
        },
      },
      "../lib/tools.js": {
        isPortReachable: async () => false,
        sleep: async () => {},
      },
      "../lib/wol.js": {
        wol: async () => {
          commands.push(["wol"]);
        },
      },
      "../platform.js": {
        SamsungPlatform: controllerSamsungPlatform,
      },
      "../protocols/frame.js": { FrameSocket },
      "../protocols/index.js": {
        SmartThingsClient,
        UPnPClient: protocolUpnpClient,
        WebSocket: Socket,
      },
      "../types/index.js": {
        TizenApplication: undefined,
        TizenDeviceInfo: undefined,
      },
      "./device.js": {
        Device: controllerDevice,
      },
      "./power.js": { PowerMonitor },
      "./strict-power.js": strict === undefined ? {} : { ...strict },
    },
  );
  const televisionModule = await loadActual(
    root,
    "accessories/television",
    sourceOnly,
    {
      homebridge: {
        Categories: {},
        PlatformAccessory: homebridgePlatformAccessory,
      },
      "../device/index.js": {
        Device: televisionDevice,
      },
      "../lib/identifiers.js": {
        withInputIdentifiers: (value: unknown) => value,
      },
      "../platform.js": {
        SamsungPlatform: televisionSamsungPlatform,
      },
      "../services/index.js": {
        InformationService: informationService,
        InputService: inputService,
        SpeakerService: speakerService,
        TelevisionService: televisionService,
        VolumeService: volumeService,
      },
      "../types/index.js": { LinkedService: undefined },
    },
  );

  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- actual full module with the fixed public controller interface.
  const controllerApi = controllerModule as ControllerModule;
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- actual full module; call its real public setter with a controlled device.
  const televisionApi = televisionModule as TelevisionModule;

  assert.equal(typeof controllerApi.DeviceController, "function");
  assert.equal(typeof televisionApi.TelevisionAccessory, "function");

  function fixture(strictSelected: boolean, initialPower: boolean) {
    const device: FixtureDevice = {
      isFrame: true,
      power: initialPower,
      config: { ip: "192.0.2.1", mac: "00:00:5e:00:53:01" },
      cache: { flush() {} },
      hasOption: (option) => strictSelected && option === "PowerState.Strict",
      setPower: async () => {
        throw new Error("Fixture power bridge not attached");
      },
      setArtMode: async () => {
        throw new Error("Fixture art bridge not attached");
      },
    };
    const controller = new controllerApi.DeviceController(device, {});
    const calls: ConsumerCall[] = [];
    device.setPower = async (value) => {
      calls.push(["guarded-power", value]);
      if (value) await controller.powerOn();
      else await controller.powerOff();
    };
    device.setArtMode = async (value) => {
      calls.push(["art-mode", value]);
      await controller.setArtMode(value);
    };
    return { controller, device, calls };
  }

  // The raw upstream Frame path is intentional when strict is not selected.
  // Exercise both art directions through the real controller and accessory.
  for (const value of [false, true]) {
    const legacy = fixture(false, true);
    commands.length = 0;
    try {
      await televisionApi.TelevisionAccessory.prototype.setMain.call(
        { device: legacy.device },
        value,
      );
      assert.deepEqual(legacy.calls, [["art-mode", !value]]);
      assert.deepEqual(commands, [["art", !value]]);
      commands.length = 0;
      await legacy.controller.setArtMode(value);
      assert.deepEqual(commands, [["art", value]]);
    } finally {
      legacy.controller.destroy();
    }
  }
  if (legacyOnly) return;

  assert.ok(strict);
  assert.equal(typeof strict.UnsupportedStrictPowerError, "function");
  for (const initialPower of [false, true]) {
    for (const value of [false, true]) {
      const selected = fixture(true, initialPower);
      commands.length = 0;
      try {
        // Root fix must route TV On/Off through strict power, not art mode.
        await assert.rejects(
          televisionApi.TelevisionAccessory.prototype.setMain.call(
            { device: selected.device },
            value,
          ),
          strict.UnsupportedStrictPowerError,
        );
        assert.deepEqual(selected.calls, [["guarded-power", value]]);
        assert.deepEqual(
          commands,
          [],
          "A strict Frame TV must receive no WOL/key/art command",
        );
        await assert.rejects(
          selected.controller.setArtMode(value),
          strict.UnsupportedStrictPowerError,
        );
        assert.deepEqual(
          commands,
          [],
          "Direct art setters must fail before a send or wake",
        );
      } finally {
        selected.controller.destroy();
      }
    }
  }
}

export async function checkInflightDestroy(
  strict: StrictConsumerModule,
): Promise<void> {
  let entered: () => void = observationNotInitialized;
  const started = new Promise<void>((resolve) => {
    entered = resolve;
  });
  let sends = 0;
  const controller = new strict.StrictPowerCommands({
    observe: (signal) =>
      new Promise<boolean>((_resolve, reject) => {
        signal.throwIfAborted();
        signal.addEventListener("abort", () => reject(signal.reason), {
          once: true,
        });
        entered();
      }),
    send: async () => {
      sends++;
    },
    confirmed: () => {
      throw new Error("Aborted observation cannot confirm power");
    },
  });
  const first = controller.set(false);
  const queued = controller.set(false);
  // Attach rejection handlers before destruction; do not create unhandled promises.
  const firstRejected = assert.rejects(first, /destroyed/);
  const queuedRejected = assert.rejects(queued, /destroyed/);
  await started;
  controller.destroy();
  await Promise.all([firstRejected, queuedRejected]);
  assert.equal(
    sends,
    0,
    "In-flight abort and queued cancellation must send nothing",
  );
  await assert.rejects(controller.observe(), /destroyed/);
}
