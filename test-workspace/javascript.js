/**
 * theme_preview.js — JavaScript syntax showcase
 * Covers: classes, closures, generators, proxies, symbols, WeakMaps,
 *         destructuring, tagged templates, iterators, regex, async patterns
 */

'use strict';

// ── Symbols & well-known symbols ───────────────────────────────────────────────
const TYPE   = Symbol('type');
const HIDDEN = Symbol.for('hidden');

// ── Regex ──────────────────────────────────────────────────────────────────────
const EMAIL_RE = /^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/;
const HEX_RE   = /^#(?:[0-9a-fA-F]{3}){1,2}$/;

// ── Tagged template ───────────────────────────────────────────────────────────
function css(strings, ...values) {
  return strings.reduce((acc, str, i) =>
    acc + str + (values[i] !== undefined ? String(values[i]) : ''), '');
}

const color   = '#09fbd3';
const padding = 12;
const styles  = css`
  background: ${color};
  padding: ${padding}px;
  border-radius: 6px;
`;

// ── Generator ─────────────────────────────────────────────────────────────────
function* fibonacci() {
  let [a, b] = [0, 1];
  while (true) {
    yield a;
    [a, b] = [b, a + b];
  }
}

function take(n, iter) {
  const result = [];
  for (const value of iter) {
    result.push(value);
    if (result.length >= n) break;
  }
  return result;
}

// ── WeakMap-backed private state ───────────────────────────────────────────────
const _private = new WeakMap();

class EventBus {
  constructor() {
    _private.set(this, { listeners: new Map() });
  }

  on(event, handler) {
    const { listeners } = _private.get(this);
    if (!listeners.has(event)) listeners.set(event, new Set());
    listeners.get(event).add(handler);
    return () => listeners.get(event)?.delete(handler); // returns unsubscribe fn
  }

  emit(event, ...args) {
    _private.get(this).listeners.get(event)?.forEach(h => h(...args));
  }
}

// ── Proxy for validation ───────────────────────────────────────────────────────
function createValidated(schema) {
  const data = {};
  return new Proxy(data, {
    set(target, key, value) {
      const validate = schema[key];
      if (validate && !validate(value)) {
        throw new TypeError(`Invalid value for "${String(key)}": ${value}`);
      }
      target[key] = value;
      return true;
    },
    get(target, key) {
      return key in target ? target[key] : undefined;
    }
  });
}

const user = createValidated({
  age:   v => Number.isInteger(v) && v >= 0 && v <= 150,
  email: v => EMAIL_RE.test(v),
  color: v => HEX_RE.test(v),
});

// ── Async iterator ─────────────────────────────────────────────────────────────
async function* paginate(fetchPage, maxPages = 10) {
  let page = 1;
  while (page <= maxPages) {
    const { items, hasNext } = await fetchPage(page++);
    yield* items;
    if (!hasNext) return;
  }
}

// ── Promise combinators ────────────────────────────────────────────────────────
async function fetchAll(urls) {
  const results = await Promise.allSettled(
    urls.map(url => fetch(url).then(r => r.json()))
  );

  return results.reduce((acc, result, i) => {
    if (result.status === 'fulfilled') {
      acc.succeeded.push({ url: urls[i], data: result.value });
    } else {
      acc.failed.push({ url: urls[i], reason: result.reason.message });
    }
    return acc;
  }, { succeeded: [], failed: [] });
}

// ── Closure / memoize ─────────────────────────────────────────────────────────
function memoize(fn, { maxSize = 100, ttl = Infinity } = {}) {
  const cache  = new Map();
  const expiry = new Map();

  return function memoized(...args) {
    const key = JSON.stringify(args);
    const now = Date.now();

    if (cache.has(key) && now < (expiry.get(key) ?? Infinity)) {
      return cache.get(key);
    }

    if (cache.size >= maxSize) {
      const oldest = cache.keys().next().value;
      cache.delete(oldest);
      expiry.delete(oldest);
    }

    const value = fn.apply(this, args);
    cache.set(key, value);
    if (ttl !== Infinity) expiry.set(key, now + ttl);
    return value;
  };
}

const expensiveCalc = memoize((n) => {
  let result = 0n;
  for (let i = 1n; i <= BigInt(n); i++) result += i ** 2n;
  return result;
}, { ttl: 60_000 });

// ── Destructuring & spreading ─────────────────────────────────────────────────
const matrix = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];
const [[a, , b], , [c]] = matrix;

const defaults = { timeout: 3000, retries: 3, verbose: false };
const config   = { ...defaults, timeout: 5000, baseUrl: 'https://api.example.com' };

const { baseUrl, timeout: reqTimeout, retries, ...rest } = config;

// ── Entry point ───────────────────────────────────────────────────────────────
const bus = new EventBus();
const unsub = bus.on('data', payload => console.log('received:', payload));
bus.emit('data', { id: 42, value: 'hello' });
unsub();

console.log('Fibonacci(10):', take(10, fibonacci()));
console.log('Sum of squares(100):', expensiveCalc(100));
