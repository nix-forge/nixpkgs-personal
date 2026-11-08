// This function is serialized for Electron. Keep its helpers inside the function.
interface Server {
  id: string;
  name: string;
  url: string;
  savePassword: boolean;
  [key: string]: unknown;
}
declare const window: {
  api: {
    localSettings: {
      passwordSet(password: string, id: string): Promise<boolean>;
    };
  };
};
async function updateAuthentication(
  server: Server,
  password: string,
): Promise<void> {
  // oxlint-disable-next-line unicorn/consistent-function-scoping -- Electron serializes this function without its module scope.
  function record(value: unknown): value is Record<string, unknown> {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }
  const store: unknown = JSON.parse(
    localStorage.getItem("store_authentication") ||
      '{"state":{"serverList":{}},"version":2}',
  );
  if (
    !record(store) ||
    store["version"] !== 2 ||
    !record(store["state"]) ||
    !record(store["state"]["serverList"])
  )
    throw new Error("Unsupported Feishin authentication store");
  const servers = store["state"]["serverList"];
  const existing = Object.values(servers).find(
    (item) =>
      record(item) &&
      (item["url"] === server.url || item["name"] === server.name),
  );
  if (
    existing !== undefined &&
    (!record(existing) || typeof existing["id"] !== "string")
  )
    throw new Error("Invalid Feishin server identity");
  if (record(existing)) {
    if (typeof existing["id"] !== "string")
      throw new Error("Invalid Feishin server identity");
    server.id = existing["id"];
  }
  server.savePassword = await window.api.localSettings.passwordSet(
    password,
    server.id,
  );
  servers[server.id] = { ...(record(existing) ? existing : {}), ...server };
  store["state"]["currentServer"] = servers[server.id];
  localStorage.setItem("store_authentication", JSON.stringify(store));
}
export = { updateAuthentication };
