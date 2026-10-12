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
// Each stands for the window's own and reaches it directly (dommy's
// `__rbWindowMember`), not through whatever the window answers for the name,
// which is this very function (see browser_globals.js).
const __rbTimerForward = globalThis.__rbWindowForward || ((fn) => fn);
const __rbTimerMember = globalThis.__rbWindowMember || ((name) => window[name]);
// The signatures are the IDL's (HTML "timers"): `setTimeout(handler, timeout
// = 0, ...arguments)` hands the extra arguments to the handler, and the
// defaults keep each function's `length` the IDL's (1, 0, 1, 0, 1, 1).
globalThis.setTimeout = __rbTimerForward(function setTimeout(handler, timeout = 0, ...args) {
  return __rbDefer((f, d) => __rbTimerMember("setTimeout").call(window, f, d, ...args), handler, timeout);
});
globalThis.clearTimeout = __rbTimerForward(function clearTimeout(id = 0) { return __rbTimerMember("clearTimeout").call(window, id); });
globalThis.setInterval = __rbTimerForward(function setInterval(handler, timeout = 0, ...args) {
  return __rbDefer((f, d) => __rbTimerMember("setInterval").call(window, f, d, ...args), handler, timeout);
});
globalThis.clearInterval = __rbTimerForward(function clearInterval(id = 0) { return __rbTimerMember("clearInterval").call(window, id); });
globalThis.requestAnimationFrame = __rbTimerForward(function requestAnimationFrame(callback) {
  return __rbDefer((f) => __rbTimerMember("requestAnimationFrame").call(window, f), callback);
});
globalThis.cancelAnimationFrame = __rbTimerForward(function cancelAnimationFrame(handle) {
  return __rbTimerMember("cancelAnimationFrame").call(window, handle);
});
// queueMicrotask must share the engine's promise-job (microtask) queue so its
// callbacks are FIFO-ordered with Promise reactions (the WHATWG
// single-microtask-queue model). Routing through the Ruby scheduler instead
// would drain on a separate pass, reordering it after all native promise jobs.
// What the callback throws is reported at the window (HTML "report an
// exception"), as window.queueMicrotask's is, rather than rejecting a promise
// nobody holds.
globalThis.queueMicrotask = __rbTimerForward(function queueMicrotask(callback) {
  if (typeof callback !== "function") throw new TypeError("queueMicrotask requires a function");
  Promise.resolve().then(() => {
    try {
      callback();
    } catch (error) {
      __rbTimerMember("reportError").call(window, error);
    }
  });
});
