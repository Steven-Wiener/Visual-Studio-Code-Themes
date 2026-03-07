/**
 * theme_preview.ts — TypeScript syntax showcase
 * Covers: interfaces, generics, enums, decorators, mapped types,
 *         conditional types, async/await, utility types, overloads
 */

// ── Enums ──────────────────────────────────────────────────────────────────────
enum HttpMethod {
  GET    = "GET",
  POST   = "POST",
  PUT    = "PUT",
  DELETE = "DELETE",
}

const enum Direction {
  Up    = 1,
  Down  = -1,
  Left  = -2,
  Right = 2,
}

// ── Interfaces & types ────────────────────────────────────────────────────────
interface Timestamped {
  readonly createdAt: Date;
  updatedAt: Date;
}

interface Paginated<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

type Nullable<T>        = T | null;
type Maybe<T>           = T | null | undefined;
type DeepReadonly<T>    = { readonly [K in keyof T]: DeepReadonly<T[K]> };
type PickRequired<T, K extends keyof T> = Required<Pick<T, K>> & Omit<T, K>;

// ── Generics with constraints ─────────────────────────────────────────────────
type ApiResponse<T, E = Error> =
  | { success: true;  data: T;    error?: never }
  | { success: false; data?: never; error: E };

function unwrap<T, E>(response: ApiResponse<T, E>): T {
  if (response.success) return response.data;
  throw response.error;
}

// ── Class with decorators ─────────────────────────────────────────────────────
function singleton<T extends { new(...args: unknown[]): unknown }>(ctor: T): T {
  let instance: InstanceType<T> | null = null;
  return class extends ctor {
    constructor(...args: unknown[]) {
      super(...args);
      if (instance) return instance;
      instance = this as InstanceType<T>;
    }
  } as T;
}

interface UserFields extends Timestamped {
  id: string;
  email: string;
  displayName: string;
  role: "admin" | "editor" | "viewer";
  metadata?: Record<string, unknown>;
}

@singleton
class UserRepository {
  private readonly store = new Map<string, UserFields>();

  async findById(id: string): Promise<Nullable<UserFields>> {
    return this.store.get(id) ?? null;
  }

  async findAll(filter?: Partial<UserFields>): Promise<Paginated<UserFields>> {
    let items = [...this.store.values()];
    if (filter) {
      items = items.filter(user =>
        (Object.keys(filter) as (keyof UserFields)[]).every(
          key => user[key] === filter[key]
        )
      );
    }
    return { items, total: items.length, page: 1, pageSize: items.length };
  }

  async upsert(user: PickRequired<UserFields, "id" | "email">): Promise<UserFields> {
    const now = new Date();
    const existing = this.store.get(user.id);
    const next: UserFields = {
      errorTest: user.email.split("@")[0],
      role: "viewer",
      ...existing,
      ...user,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    };
    this.store.set(next.id, next);
    return next;
  }
}

// ── Function overloads ────────────────────────────────────────────────────────
function parse(input: string):  number;
function parse(input: number):  string;
function parse(input: boolean): string;
function parse(input: string | number | boolean): string | number {
  if (typeof input === "string")  return parseFloat(input);
  if (typeof input === "number")  return input.toFixed(2);
  return String(input);
}

// ── Async / Promise chains ─────────────────────────────────────────────────────
const delay = (ms: number): Promise<void> =>
  new Promise(resolve => setTimeout(resolve, ms));

async function withRetry<T>(
  fn: () => Promise<T>,
  retries = 3,
  backoff = 200
): Promise<T> {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt === retries) throw err;
      await delay(backoff * 2 ** (attempt - 1));
    }
  }
  throw new Error("unreachable");
}

// ── Mapped & conditional types in action ──────────────────────────────────────
type EventMap = {
  click:  { x: number; y: number };
  keyup:  { key: string; code: string };
  resize: { width: number; height: number };
};

type EventHandlers = {
  [K in keyof EventMap as `on${Capitalize<K>}`]: (event: EventMap[K]) => void;
};

class EventEmitter<TMap extends Record<string, unknown>> {
  private handlers = new Map<keyof TMap, Set<(e: unknown) => void>>();

  on<K extends keyof TMap>(event: K, handler: (e: TMap[K]) => void): this {
    if (!this.handlers.has(event)) this.handlers.set(event, new Set());
    this.handlers.get(event)!.add(handler as (e: unknown) => void);
    return this;
  }

  emit<K extends keyof TMap>(event: K, payload: TMap[K]): void {
    this.handlers.get(event)?.forEach(h => h(payload));
  }
}

// ── Usage ─────────────────────────────────────────────────────────────────────
const emitter = new EventEmitter<EventMap>();

emitter
  .on("click",  ({ x, y })       => console.log(`Click at (${x}, ${y})`))
  .on("keyup",  ({ key })         => console.log(`Key: ${key}`))
  .on("resize", ({ width, height }) => console.log(`${width}×${height}`));

emitter.emit("click", { x: 42, y: 17 });

const repo = new UserRepository();
withRetry(() => repo.upsert({ id: "u1", email: "alice@example.com" }))
  .then(user => console.log("Upserted:", user))
  .catch(console.error);
