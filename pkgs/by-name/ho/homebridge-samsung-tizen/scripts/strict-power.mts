import { setTimeout as pause } from "node:timers/promises";

export class UnsupportedStrictPowerError extends Error {}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function soapElement(
  parent: Record<string, unknown>,
  name: string,
  namespace: string,
  inherited: Record<string, string>,
): { value: Record<string, unknown>; namespaces: Record<string, string> } {
  const entries = Object.entries(parent).filter(
    ([key]) => !key.startsWith("@_") && key.split(":").at(-1) === name,
  );
  const entry = entries[0];
  if (entries.length !== 1 || !entry || !isRecord(entry[1]))
    throw new Error("Invalid SOAP element");
  const [key, value] = entry;
  const namespaces = { ...inherited };
  for (const [attribute, uri] of Object.entries(value)) {
    if (attribute === "@_xmlns" && typeof uri === "string")
      namespaces[""] = uri;
    if (attribute.startsWith("@_xmlns:") && typeof uri === "string")
      namespaces[attribute.slice(8)] = uri;
  }
  const prefix = key.includes(":") ? key.split(":")[0] : "";
  if (prefix === undefined || namespaces[prefix] !== namespace)
    throw new Error("Invalid SOAP namespace");
  return { value, namespaces };
}

// Reading an awake network endpoint does not establish panel power. Require
// both the model's HTTP field and its read-only rendering-service observation.
export async function observeStrictPower(
  ip: string,
  signal: AbortSignal,
  request: typeof fetch,
  parseXml: (xml: string) => unknown,
): Promise<boolean> {
  const response = await request(`http://${ip}:8001/api/v2/`, { signal });
  if (!response.ok) throw new Error("Unable to read TV power state");
  const info: unknown = await response.json();
  if (!isRecord(info) || !isRecord(info["device"])) {
    throw new Error("Unable to determine TV power state");
  }
  const device = info["device"];
  if (device["FrameTVSupport"] === "true") {
    throw new UnsupportedStrictPowerError(
      "Strict power state requires a verified non-Frame TV",
    );
  }
  const state = device["PowerState"];
  if (
    typeof state !== "string" ||
    !["on", "", "standby", "off"].includes(state)
  ) {
    throw new Error("Unable to determine TV power state");
  }

  const urn = "urn:schemas-upnp-org:service:RenderingControl:1";
  let active: boolean;
  try {
    const rendering = await request(
      `http://${ip}:9197/upnp/control/RenderingControl1`,
      {
        method: "POST",
        headers: {
          "Content-Type": "text/xml; charset=utf-8",
          SOAPAction: `"${urn}#GetVolume"`,
        },
        body: `<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:GetVolume xmlns:u="${urn}"><InstanceID>0</InstanceID><Channel>Master</Channel></u:GetVolume></s:Body></s:Envelope>`,
        signal,
      },
    );
    const xml = await rendering.text();
    if (!rendering.ok || /<!(?:DOCTYPE|ENTITY)\b/i.test(xml)) {
      throw new Error("Unable to determine TV rendering activity");
    }
    const parsed = parseXml(xml);
    if (!isRecord(parsed)) throw new Error("Invalid SOAP response");
    const envelope = soapElement(
      parsed,
      "Envelope",
      "http://schemas.xmlsoap.org/soap/envelope/",
      {},
    );
    const body = soapElement(
      envelope.value,
      "Body",
      "http://schemas.xmlsoap.org/soap/envelope/",
      envelope.namespaces,
    );
    const result = soapElement(
      body.value,
      "GetVolumeResponse",
      urn,
      body.namespaces,
    );
    const volume = result.value["CurrentVolume"];
    if (
      typeof volume !== "string" ||
      !/^\d{1,3}$/.test(volume) ||
      Number(volume) > 100
    ) {
      throw new Error("Unable to determine TV rendering activity");
    }
    active = true;
  } catch (error) {
    if (
      isRecord(error) &&
      isRecord(error["cause"]) &&
      error["cause"]["code"] === "ECONNREFUSED"
    ) {
      active = false;
    } else {
      throw error;
    }
  }
  if (state === "on" && active) return true;
  if (state !== "on" && !active) return false;
  throw new Error("Conflicting TV power observations");
}

export interface StrictPowerAdapter {
  observe(signal: AbortSignal): Promise<boolean>;
  send(value: boolean, observed: boolean | undefined): Promise<void>;
  confirmed(value: boolean): void;
}

export class StrictPowerCommands {
  private adapter: StrictPowerAdapter;
  private operation: Promise<void> | null = null;
  private unconfirmed: boolean | undefined;
  private abort = new AbortController();
  private now: () => number;
  private delay: (ms: number, signal: AbortSignal) => Promise<void>;

  constructor(
    adapter: StrictPowerAdapter,
    now: () => number = () => performance.now(),
    delay: (ms: number, signal: AbortSignal) => Promise<void> = async (
      ms,
      signal,
    ) => {
      await pause(ms, undefined, { signal });
    },
  ) {
    this.adapter = adapter;
    this.now = now;
    this.delay = delay;
  }

  async observe(
    signal: AbortSignal = AbortSignal.timeout(3000),
  ): Promise<boolean> {
    this.abort.signal.throwIfAborted();
    const value = await this.adapter.observe(
      AbortSignal.any([this.abort.signal, signal]),
    );
    this.abort.signal.throwIfAborted();
    signal.throwIfAborted();
    this.adapter.confirmed(value);
    return value;
  }

  async set(value: boolean): Promise<void> {
    this.abort.signal.throwIfAborted();
    const previous = this.operation ?? Promise.resolve();
    const operation = previous
      .catch(() => {})
      .then(async () => {
        this.abort.signal.throwIfAborted();
        if (this.unconfirmed !== undefined) {
          await this.waitFor(this.unconfirmed);
          this.unconfirmed = undefined;
        }
        let observed: boolean | undefined;
        try {
          observed = await this.observe();
        } catch (error) {
          if (
            !value ||
            error instanceof UnsupportedStrictPowerError ||
            this.abort.signal.aborted
          )
            throw error;
          // Unknown On may send only WOL. Unknown Off never authorizes a toggle.
        }
        if (observed === value) return;
        this.unconfirmed = value;
        await this.adapter.send(value, observed);
        await this.waitFor(value);
        this.unconfirmed = undefined;
      });
    this.operation = operation;
    try {
      await operation;
    } finally {
      if (this.operation === operation) this.operation = null;
    }
  }

  async settled(): Promise<void> {
    if (this.operation) await this.operation;
    if (this.unconfirmed !== undefined) await this.waitFor(this.unconfirmed);
  }

  destroy(): void {
    this.abort.abort(new Error("TV power controller was destroyed"));
  }

  private async waitFor(value: boolean): Promise<void> {
    const deadline = this.now() + 15000;
    const signal = AbortSignal.timeout(15000);
    // These model-specific HTTP/UPnP observations have no notification API.
    // Keep the original positive backoff and one overall confirmation deadline.
    // Serial physical confirmation must not overlap observations or delays; the
    // typed and untyped lint boundaries preserve this required await-in-loop.
    while (this.now() < deadline) {
      signal.throwIfAborted();
      try {
        if ((await this.observe(signal)) === value && this.now() < deadline)
          return;
      } catch (error) {
        if (
          error instanceof UnsupportedStrictPowerError ||
          this.abort.signal.aborted
        )
          throw error;
      }
      const remaining = deadline - this.now();
      if (remaining <= 0) break;
      await this.delay(
        Math.min(500, remaining),
        AbortSignal.any([this.abort.signal, signal]),
      );
    }
    throw new Error(
      "TV power transition was not confirmed; refusing another toggle",
    );
  }
}
