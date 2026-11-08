// Exchange the website password for a revocable application key before storing
// a browser session. Never write website passwords into browser storage.
export interface Auth {
  server: string;
  token?: string;
  username: string;
  password: string;
}
export interface RequestOptions {
  baseURL: string;
  headers: { Authorization: string };
  redirect: "error";
  method?: "POST";
  body?: { description: string };
}
export type Request = (
  path: string,
  options: RequestOptions,
) => Promise<unknown>;
function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
export const exchangePasswordForToken = async (
  auth: Auth,
  request: Request,
  origin: string,
): Promise<Required<Auth>> => {
  const { server, token, username, password } = auth;
  if (token) return { server, token, username: "", password: "" };
  const options: RequestOptions = {
    baseURL: server,
    headers: { Authorization: `Basic ${btoa(`${username}:${password}`)}` },
    redirect: "error",
  };
  const description = `ReactFlux ${origin}`;
  const keys = await request("v1/api-keys", options);
  if (!Array.isArray(keys))
    throw new Error("The server returned an invalid API key list");
  let key: unknown = keys.find(
    (item: unknown) => record(item) && item["description"] === description,
  );
  if (!key) {
    key = await request("v1/api-keys", {
      ...options,
      method: "POST",
      body: { description },
    });
  }
  if (!record(key) || typeof key["token"] !== "string" || !key["token"]) {
    throw new Error("The server could not create a browser API key");
  }
  return { server, token: key["token"], username: "", password: "" };
};
