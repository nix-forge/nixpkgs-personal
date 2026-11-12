import api = require("./scrypted-api.cjs");
// Reconcile managed plugin policy while Scrypted is stopped.
// Scrypted stores plugin settings and automation state in PluginDevice records.
import net = require("node:net");
import path = require("node:path");

interface Device {
  pluginId?: string;
  nativeId?: string | null;
  storage?: Record<string, unknown> | null;
  state?: {
    on?: { value?: boolean; [key: string]: unknown };
    [key: string]: unknown;
  };
}

function selectHomeKit(devices: Device[]): Device | undefined {
  const matches = devices.filter(
    (device) =>
      device.pluginId === "@scrypted/homekit" && device.nativeId == null,
  );
  if (matches.length > 1)
    throw new Error("Multiple Scrypted HomeKit provider records");
  return matches[0];
}

function configuredStorage(
  device: Device,
  address: string,
): Record<string, unknown> {
  if (net.isIP(address) !== 4)
    throw new Error("Invalid HomeKit advertisement address");
  if (
    !device.storage ||
    Array.isArray(device.storage) ||
    typeof device.storage !== "object"
  )
    throw new Error("Invalid Scrypted HomeKit storage");
  const next = { ...device.storage };
  next["advertiserOverride"] = "avahi";
  next["advertiserAddresses"] = address;
  return next;
}

function selectPluginUpdater(devices: Device[]): Device | undefined {
  const matches = devices.filter(
    (device) =>
      device.pluginId === "@scrypted/core" &&
      device.nativeId === "automation:update-plugins",
  );
  if (matches.length > 1)
    throw new Error("Multiple Scrypted plugin updater records");
  return matches[0];
}

function disabledUpdaterState(
  device: Device,
): NonNullable<Device["state"]> & { on: { value: boolean } } {
  if (typeof device.state?.on?.value !== "boolean")
    throw new Error("Invalid Scrypted plugin updater state");
  return { ...device.state, on: { ...device.state.on, value: false } };
}

async function reconcile(
  serverRoot: string,
  volume: string,
  address: string,
): Promise<"updated" | "unchanged" | "pending"> {
  if (net.isIP(address) !== 4)
    throw new Error("Invalid HomeKit advertisement address");
  const WrappedLevel = api.loadDatabase(serverRoot);
  const PluginDevice = api.loadModel(serverRoot, "PluginDevice");
  const db = new WrappedLevel(path.join(volume, "scrypted.db"));
  await db.open();
  try {
    const devices: Device[] = [];
    for await (const device of db.getAll(PluginDevice)) {
      if (!api.record(device))
        throw new Error("Invalid Scrypted device record");
      const managed =
        (device["pluginId"] === "@scrypted/homekit" &&
          device["nativeId"] == null) ||
        (device["pluginId"] === "@scrypted/core" &&
          device["nativeId"] === "automation:update-plugins");
      if (!managed) continue;
      if (!api.isDevice(device))
        throw new Error("Invalid Scrypted managed device record");
      devices.push(device);
    }
    const homekit = selectHomeKit(devices);
    const updater = selectPluginUpdater(devices);
    // Validate both records before changing either one.
    const homekitStorage = homekit && configuredStorage(homekit, address);
    const updaterState = updater && disabledUpdaterState(updater);
    let changed = false;
    if (homekit && homekitStorage) {
      if (
        homekit.storage?.["advertiserOverride"] !==
          homekitStorage["advertiserOverride"] ||
        homekit.storage?.["advertiserAddresses"] !==
          homekitStorage["advertiserAddresses"]
      ) {
        homekit.storage = homekitStorage;
        await db.upsert(homekit);
        changed = true;
      }
    }
    if (updater && updaterState) {
      if (updater.state?.on?.value) {
        updater.state = updaterState;
        await db.upsert(updater);
        changed = true;
      }
    }
    if (changed) return "updated";
    return homekit && updater ? "unchanged" : "pending";
  } finally {
    await db.close();
  }
}

export = {
  configuredStorage,
  disabledUpdaterState,
  reconcile,
  selectHomeKit,
  selectPluginUpdater,
};

if (require.main === module) {
  if (process.argv.length !== 5)
    throw new Error("Invalid Scrypted settings arguments");
  reconcile(process.argv[2]!, process.argv[3]!, process.argv[4]!)
    .then((result) => console.log(`Scrypted managed settings ${result}`))
    .catch((error: unknown) => {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
