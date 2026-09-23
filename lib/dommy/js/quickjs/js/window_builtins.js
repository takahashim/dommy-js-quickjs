// The window IS the global object, so JS built-in constructors and namespaces
// are also `window` properties (`window.String`, `window.Number`, …). Mirror
// them as own props on the window proxy so code that reads constructors off
// `window` (e.g. the WPT reflection harness's `window[type]` casts) resolves
// them.
for (const __n of [
  "String", "Boolean", "Number", "BigInt", "Symbol", "Object", "Array",
  "Function", "Date", "RegExp", "Promise", "Map", "Set", "WeakMap",
  "WeakSet", "Math", "JSON", "Reflect", "Proxy", "Error", "TypeError",
  "RangeError", "SyntaxError", "Infinity", "NaN", "undefined",
  "parseInt", "parseFloat", "isNaN", "isFinite", "globalThis",
]) {
  try { window[__n] = globalThis[__n]; } catch (__e) {}
}
