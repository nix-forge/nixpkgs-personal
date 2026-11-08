// Validate the API boundary of the selected Scrypted package before using it.
import path = require("node:path");
interface User {
  _id: string;
  token: string;
  aclId?: string;
  passwordHash?: string;
}
interface Device {
  pluginId?: string;
  nativeId?: string | null;
  storage?: Record<string, unknown> | null;
  state?: {
    on?: { value?: boolean; [key: string]: unknown };
    [key: string]: unknown;
  };
}
interface ModelRecord extends Device {
  _id?: string;
  value?: unknown;
  packageJson?: { name?: string; version?: string };
  zip?: string;
}
interface Database {
  open(): Promise<void>;
  close(): Promise<void>;
  getAll(model: unknown): AsyncIterable<unknown>;
  upsert(record: object): Promise<void>;
  batch?: (
    operations: (
      { type: "put"; key: string; value: string } | { type: "del"; key: string }
    )[],
  ) => Promise<void>;
  tryGet?: (model: unknown, id: string) => Promise<unknown>;
  getCount?: (model: unknown) => Promise<number>;
}
type DatabaseConstructor = new (file: string) => Database;
type ModelConstructor = {
  new (id?: string): ModelRecord;
  readonly name: string;
};
interface UsersAPI {
  UsersService: {
    addUserToDatabase(
      db: Database,
      username: string,
      password: string,
      extra?: undefined,
    ): Promise<unknown>;
  };
  setScryptedUserPassword(
    this: void,
    user: User,
    password: string,
    timestamp: number,
  ): void | Promise<void>;
}
function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function databaseClass(value: unknown): value is DatabaseConstructor {
  if (typeof value !== "function") return false;
  const prototype: unknown = value.prototype;
  return (
    record(prototype) &&
    ["open", "close", "getAll", "upsert"].every(
      (name) => typeof Reflect.get(prototype, name) === "function",
    )
  );
}
function modelClass(value: unknown): value is ModelConstructor {
  return typeof value === "function" && record(value.prototype);
}
function loadDatabase(serverRoot: string): DatabaseConstructor {
  const module: unknown = require(path.join(serverRoot, "dist/level.js"));
  if (!record(module) || !databaseClass(module["default"]))
    throw new Error("Scrypted database API changed");
  return module["default"];
}
function loadModel(
  serverRoot: string,
  name: "ScryptedUser" | "Settings" | "PluginDevice" | "Plugin",
): ModelConstructor {
  const module: unknown = require(path.join(serverRoot, "dist/db-types.js"));
  if (!record(module) || !modelClass(module[name]))
    throw new Error(`Scrypted ${name} model API changed`);
  return module[name];
}
function usersAPI(value: unknown): value is UsersAPI {
  return (
    record(value) &&
    (record(value["UsersService"]) ||
      typeof value["UsersService"] === "function") &&
    typeof Reflect.get(value["UsersService"], "addUserToDatabase") ===
      "function" &&
    typeof value["setScryptedUserPassword"] === "function"
  );
}
function loadUsers(serverRoot: string): UsersAPI {
  const module: unknown = require(
    path.join(serverRoot, "dist/services/users.js"),
  );
  if (!usersAPI(module))
    throw new Error("Scrypted user management API changed");
  return module;
}
function isUser(value: unknown): value is User {
  return (
    record(value) &&
    typeof value["_id"] === "string" &&
    typeof value["token"] === "string" &&
    (value["aclId"] === undefined || typeof value["aclId"] === "string") &&
    (value["passwordHash"] === undefined ||
      typeof value["passwordHash"] === "string")
  );
}
function isDevice(value: unknown): value is Device {
  if (!record(value)) return false;
  if (value["pluginId"] !== undefined && typeof value["pluginId"] !== "string")
    return false;
  if (
    value["nativeId"] !== undefined &&
    value["nativeId"] !== null &&
    typeof value["nativeId"] !== "string"
  )
    return false;
  if (
    value["storage"] !== undefined &&
    value["storage"] !== null &&
    !record(value["storage"])
  )
    return false;
  if (value["state"] !== undefined && !record(value["state"])) return false;
  return (
    !record(value["state"]) ||
    value["state"]["on"] === undefined ||
    (record(value["state"]["on"]) &&
      (value["state"]["on"]["value"] === undefined ||
        typeof value["state"]["on"]["value"] === "boolean"))
  );
}
function isPlugin(value: unknown): value is ModelRecord {
  if (!isDevice(value) || !record(value)) return false;
  if (
    value["packageJson"] !== undefined &&
    (!record(value["packageJson"]) ||
      (value["packageJson"]["name"] !== undefined &&
        typeof value["packageJson"]["name"] !== "string") ||
      (value["packageJson"]["version"] !== undefined &&
        typeof value["packageJson"]["version"] !== "string"))
  )
    return false;
  return value["zip"] === undefined || typeof value["zip"] === "string";
}
export = {
  record,
  loadDatabase,
  loadModel,
  loadUsers,
  isUser,
  isDevice,
  isPlugin,
};
