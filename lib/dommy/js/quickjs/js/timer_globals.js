// The bare timer globals a browser exposes, routed into Dommy's deterministic
// scheduler through the window (`window.setTimeout` already works via the
// Window manifest; these are the unqualified ones).
//
// Remember where each timer was scheduled, so a throwing callback can be traced
// back to the code that set it up. This matters most for minified SPA bundles,
// where the thrown value is often a bare `null` with no stack of its own — the
// only locatable stack is the scheduling site. The origin Error is kept JS-side
// and only stringified if the callback actually throws (see
// __rbFetchTimerOrigin + Runtime#handle_timer_error); a successful callback
// forgets its origin and the map is size-capped, so this stays cheap.
globalThis.__rbTimerOrigins = new Map();
const __rbDefer = (schedule, fn, delay) => {
  if (typeof fn !== "function") return schedule(fn, delay);
  const origin = new Error();
  let id;
  const wrapped = function () {
    const result = fn.apply(this, arguments);
    __rbTimerOrigins.delete(id); // ran cleanly — no need to keep it
    return result;
  };
  id = schedule(wrapped, delay);
  __rbTimerOrigins.set(id, origin);
  if (__rbTimerOrigins.size > 4096) __rbTimerOrigins.delete(__rbTimerOrigins.keys().next().value);
  return id;
};
globalThis.__rbFetchTimerOrigin = (id) => {
  const origin = __rbTimerOrigins.get(id);
  if (!origin) return "";
  __rbTimerOrigins.delete(id);
  return origin.stack || "";
};
globalThis.setTimeout = (fn, delay) => __rbDefer((f, d) => window.setTimeout(f, d), fn, delay);
globalThis.clearTimeout = (id) => window.clearTimeout(id);
globalThis.setInterval = (fn, delay) => __rbDefer((f, d) => window.setInterval(f, d), fn, delay);
globalThis.clearInterval = (id) => window.clearInterval(id);
globalThis.requestAnimationFrame = (fn) => __rbDefer((f) => window.requestAnimationFrame(f), fn);
globalThis.cancelAnimationFrame = (id) => window.cancelAnimationFrame(id);
// queueMicrotask must share the engine's promise-job (microtask) queue so its
// callbacks are FIFO-ordered with Promise reactions (the WHATWG
// single-microtask-queue model). Routing through the Ruby scheduler instead
// would drain on a separate pass, reordering it after all native promise jobs.
globalThis.queueMicrotask = (fn) => {
  if (typeof fn !== "function") throw new TypeError("queueMicrotask requires a function");
  Promise.resolve().then(() => { fn(); });
};
