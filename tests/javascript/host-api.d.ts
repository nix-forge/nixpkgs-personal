// Structural contract for the atom methods used by the injected store.
// Package builds resolve the real nanostores dependency from the upstream lockfile.
declare module "nanostores" {
  export function atom<T>(initial: T): {
    get(): T;
    set(value: T): void;
    subscribe(callback: (value: T, previous?: T) => void): () => void;
  };
}
