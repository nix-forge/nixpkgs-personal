import { atom } from "nanostores";

export interface Session {
  server: string;
  token: string;
  username: string;
  password: string;
}
const empty: Session = { server: "", token: "", username: "", password: "" };
const storageKey = "reactflux-session";
// Discard upstream's durable credential cache without migrating its password.
localStorage.removeItem("auth");
let restored = empty;
try {
  const value: unknown = JSON.parse(
    sessionStorage.getItem(storageKey) || "null",
  );
  if (
    value !== null &&
    typeof value === "object" &&
    "server" in value &&
    "token" in value &&
    typeof value.server === "string" &&
    typeof value.token === "string"
  ) {
    restored = { ...empty, server: value.server, token: value.token };
  }
} catch {
  sessionStorage.removeItem(storageKey);
}
export const authState = atom(restored);
authState.subscribe(({ server, token }) => {
  if (token)
    sessionStorage.setItem(storageKey, JSON.stringify({ server, token }));
  else sessionStorage.removeItem(storageKey);
});
export const setAuth = (changes: Session) => authState.set(changes);
export const resetAuth = () => setAuth(empty);
