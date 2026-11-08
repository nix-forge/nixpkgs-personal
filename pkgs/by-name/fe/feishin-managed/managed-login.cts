import renderer = require("./managed-login-renderer.cjs");
import fs = require("node:fs");
import path = require("node:path");

interface ManagedLogin {
  name: string;
  url: string;
  username_path: string;
  password_path: string;
}

interface LoginResponse {
  token: string;
  id: string;
  username: string;
  isAdmin?: boolean;
  subsonicSalt: string;
  subsonicToken: string;
}

interface WebContents {
  executeJavaScript(source: string): Promise<unknown>;
  reload(): void;
  getType(): string;
  getURL(): string;
  once(event: "did-finish-load", callback: () => void): void;
}

interface ElectronApp {
  getPath(name: "userData"): string;
  on(
    event: "web-contents-created",
    callback: (event: unknown, contents: WebContents) => void,
  ): void;
}

function isLoginResponse(value: unknown): value is LoginResponse {
  if (value === null || typeof value !== "object") return false;
  if (
    "isAdmin" in value &&
    value.isAdmin !== undefined &&
    typeof value.isAdmin !== "boolean"
  )
    return false;
  return ["token", "id", "username", "subsonicSalt", "subsonicToken"].every(
    (field) =>
      typeof Reflect.get(value, field) === "string" &&
      Reflect.get(value, field) !== "",
  );
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function isManagedLogin(value: unknown): value is ManagedLogin {
  return (
    record(value) &&
    ["name", "url", "username_path", "password_path"].every(
      (field) => typeof value[field] === "string" && value[field] !== "",
    )
  );
}
function configurePlayer(
  store: { set(key: string, value: string): void },
  settingsPath: string,
): void {
  if (!fs.existsSync(settingsPath)) return;
  const settings: unknown = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
  if (!record(settings)) throw new Error("Invalid managed player settings");
  if (
    settings["mpv_path"] !== undefined &&
    typeof settings["mpv_path"] !== "string"
  )
    throw new Error("Invalid managed mpv path");
  if (settings["mpv_path"]) store.set("mpv_path", settings["mpv_path"]);
}

async function provision(
  contents: Pick<WebContents, "executeJavaScript" | "reload">,
  settingsPath: string,
  fetchImpl: typeof fetch = fetch,
): Promise<boolean> {
  if (!fs.existsSync(settingsPath)) return false;
  const settings: unknown = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
  if (!record(settings)) throw new Error("Invalid managed login settings");
  const managed = settings["managed_login"];
  if (managed === undefined) return false;
  if (!isManagedLogin(managed))
    throw new Error("Invalid managed login configuration");
  const username = fs.readFileSync(managed.username_path, "utf8").trim();
  const password = fs.readFileSync(managed.password_path, "utf8").trim();
  const url = managed.url.replace(/\/$/, "");
  const response = await fetchImpl(`${url}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error("Managed music login failed");
  const login: unknown = await response.json();
  if (!isLoginResponse(login)) {
    throw new Error("Managed music login returned incomplete credentials");
  }
  const server = {
    id: "nix-managed-navidrome",
    name: managed.name,
    type: "navidrome",
    url,
    username: login.username,
    userId: login.id,
    isAdmin: Boolean(login.isAdmin),
    credential: new URLSearchParams({
      u: username,
      s: login.subsonicSalt,
      t: login.subsonicToken,
    }).toString(),
    ndCredential: login.token,
    savePassword: true,
  };
  await contents.executeJavaScript(
    `(${renderer.updateAuthentication.toString()})(${JSON.stringify(server)}, ${JSON.stringify(password)})`,
  );
  contents.reload();
  return true;
}

function install({ app }: { app: ElectronApp }): void {
  app.on("web-contents-created", (_event, contents) => {
    if (contents.getType() !== "window") return;
    contents.once("did-finish-load", () => {
      if (
        !contents
          .getURL()
          .split(/[?#]/)[0]
          ?.endsWith("/out/renderer/index.html")
      )
        return;
      provision(
        contents,
        path.join(app.getPath("userData"), "managed.json"),
      ).catch(() =>
        console.error(
          "Feishin managed login failed; check the server and sealed credential files.",
        ),
      );
    });
  });
}

export = { configurePlayer, install, provision };
