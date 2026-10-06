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
// The signatures are the IDL's (HTML "timers"): `setTimeout(handler, timeout
// = 0, ...arguments)` hands the extra arguments to the handler, and the
// defaults keep each function's `length` the IDL's (1, 0, 1, 0, 1, 1).
globalThis.setTimeout = function setTimeout(handler, timeout = 0, ...args) {
  return __rbDefer((f, d) => window.setTimeout(f, d, ...args), handler, timeout);
};
globalThis.clearTimeout = function clearTimeout(id = 0) { return window.clearTimeout(id); };
globalThis.setInterval = function setInterval(handler, timeout = 0, ...args) {
  return __rbDefer((f, d) => window.setInterval(f, d, ...args), handler, timeout);
};
globalThis.clearInterval = function clearInterval(id = 0) { return window.clearInterval(id); };
globalThis.requestAnimationFrame = function requestAnimationFrame(callback) {
  return __rbDefer((f) => window.requestAnimationFrame(f), callback);
};
globalThis.cancelAnimationFrame = function cancelAnimationFrame(handle) {
  return window.cancelAnimationFrame(handle);
};
// queueMicrotask must share the engine's promise-job (microtask) queue so its
// callbacks are FIFO-ordered with Promise reactions (the WHATWG
// single-microtask-queue model). Routing through the Ruby scheduler instead
// would drain on a separate pass, reordering it after all native promise jobs.
globalThis.queueMicrotask = function queueMicrotask(callback) {
  if (typeof callback !== "function") throw new TypeError("queueMicrotask requires a function");
  Promise.resolve().then(() => { callback(); });
};
