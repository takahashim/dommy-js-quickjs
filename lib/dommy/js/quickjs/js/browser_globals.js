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
globalThis.getComputedStyle = (...args) => window.getComputedStyle(...args);
globalThis.matchMedia = (...args) => window.matchMedia(...args);
globalThis.fetch = (...args) => window.fetch(...args);
globalThis.addEventListener = (...args) => window.addEventListener(...args);
globalThis.removeEventListener = (...args) => window.removeEventListener(...args);
globalThis.dispatchEvent = (event) => window.dispatchEvent(event);

// More bare globals frameworks read directly (e.g. performance.now(), crypto,
// screen). Objects/values are aliased by reference; methods are wrapped so
// `this` binds to the window. All already exist on window.
for (const __n of ["performance", "crypto", "screen", "visualViewport",
                   "indexedDB", "caches", "devicePixelRatio",
                   "innerWidth", "innerHeight", "scrollX", "scrollY", "pageXOffset"]) {
  try { globalThis[__n] = window[__n]; } catch (__e) {}
}
for (const __m of ["scrollTo", "scrollBy", "requestIdleCallback", "cancelIdleCallback",
                   "getSelection", "structuredClone", "reportError", "btoa", "atob",
                   "alert", "confirm", "prompt", "open", "postMessage"]) {
  try { globalThis[__m] = (...args) => window[__m](...args); } catch (__e) {}
}
