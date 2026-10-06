// The bare browser globals frameworks reach for, aliased onto the installed
// window. This is what lets real frontend bundles (Turbo, …) run unmodified.
globalThis.self = globalThis;
// Top-level window: parent/top are the window itself (spec), so frame-walking
// loops terminate instead of dereferencing undefined.
globalThis.parent = globalThis;
globalThis.top = globalThis;
// `frames` is the window itself, indexable by child-frame number
// (`frames[0]` === the first <iframe>'s contentWindow).
globalThis.frames = window;
globalThis.location = window.location;
globalThis.history = window.history;
globalThis.navigator = window.navigator;
globalThis.sessionStorage = window.sessionStorage;
globalThis.localStorage = window.localStorage;
globalThis.CSS = window.CSS;
// A bare window method forwards to the window, named and sized as the IDL
// declares it (`structuredClone.length` is 1, not a rest wrapper's 0): the
// generated signatures dommy loads give each operation's required-argument
// count, looked up along the interface's inheritance (EventTarget's
// addEventListener).
const __rbWindowOperation = (name) => {
  const signatures = globalThis.__rbIdlSignatures || {};
  for (let iface = "Window"; iface && signatures[iface]; iface = signatures[iface].inherits) {
    const operation = (signatures[iface].operations || {})[name];
    if (operation) return operation;
  }
  return null;
};
const __rbForwardWindowMethod = (name) => {
  const forward = function (...args) { return window[name](...args); };
  const operation = __rbWindowOperation(name);
  Object.defineProperty(forward, "name", { value: name });
  Object.defineProperty(forward, "length", { value: operation ? operation.required : 0 });
  globalThis[name] = forward;
};
for (const __m of ["getComputedStyle", "matchMedia", "fetch",
                   "addEventListener", "removeEventListener", "dispatchEvent"]) {
  __rbForwardWindowMethod(__m);
}

// More bare globals frameworks read directly (e.g. performance.now(), crypto,
// screen). Objects the window always returns the same of are aliased by
// reference; methods forward (above) so `this` binds to the window.
for (const __n of ["performance", "crypto", "screen", "visualViewport",
                   "indexedDB", "caches"]) {
  try { globalThis[__n] = window[__n]; } catch (__e) {}
}
// Values that change (a resize, a scroll) are read from the window each time
// rather than copied once at boot. They are [Replaceable]: an assignment
// replaces the accessor with the assigned value, as on a real window.
for (const __n of ["devicePixelRatio", "innerWidth", "innerHeight",
                   "scrollX", "scrollY", "pageXOffset", "pageYOffset"]) {
  try {
    Object.defineProperty(globalThis, __n, {
      get() { return window[__n]; },
      set(value) {
        Object.defineProperty(globalThis, __n, { value, writable: true, enumerable: true, configurable: true });
      },
      enumerable: true,
      configurable: true,
    });
  } catch (__e) {}
}
for (const __m of ["scrollTo", "scrollBy", "requestIdleCallback", "cancelIdleCallback",
                   "getSelection", "structuredClone", "reportError", "btoa", "atob",
                   "alert", "confirm", "prompt", "open", "postMessage"]) {
  try { __rbForwardWindowMethod(__m); } catch (__e) {}
}
