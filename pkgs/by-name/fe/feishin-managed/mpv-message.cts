// mpv IPC frames arrive as JSON; validate envelope fields before dispatching.
interface Message {
  event?: string;
  name?: string;
  data?: unknown;
  error?: string;
  request_id?: number;
}
function parseMessage(source: string): Message {
  const value: unknown = JSON.parse(source);
  if (value === null || typeof value !== "object" || Array.isArray(value))
    throw new Error("Invalid mpv IPC message");
  for (const name of ["event", "name", "error"])
    if (
      Reflect.get(value, name) !== undefined &&
      typeof Reflect.get(value, name) !== "string"
    )
      throw new Error("Invalid mpv IPC field");
  const id: unknown = Reflect.get(value, "request_id");
  if (id !== undefined && (typeof id !== "number" || !Number.isSafeInteger(id)))
    throw new Error("Invalid mpv request ID");
  return value;
}
export = { parseMessage };
