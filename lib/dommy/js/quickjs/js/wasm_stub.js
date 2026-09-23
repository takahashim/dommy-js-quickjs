// This QuickJS build has no WebAssembly, so a bare `WebAssembly.foo` reference
// throws `'WebAssembly' is not defined` (nuxt.com via Shiki, many bundlers'
// feature probes). Define a stub: compile/instantiate reject and validate()
// returns false, so WASM-loading code takes its JS fallback instead of
// crashing.
//
// `Memory` honors `{shared:true}` with a SharedArrayBuffer, which the engine
// does ship. That is also what WPT's common/sab.js needs: it derives the SAB
// constructor from `new WebAssembly.Memory({shared:true}).buffer.constructor`.
if (typeof globalThis.WebAssembly === "undefined") {
  var unsupported = function () { return Promise.reject(new Error("WebAssembly is not supported")); };
  var throwUnsupported = function () { throw new Error("WebAssembly is not supported"); };
  globalThis.WebAssembly = {
    instantiate: unsupported, instantiateStreaming: unsupported,
    compile: unsupported, compileStreaming: unsupported,
    validate: function () { return false; },
    Module: throwUnsupported, Instance: throwUnsupported,
    Memory: function (opts) {
      var bytes = ((opts && opts.initial) || 0) * 65536;
      this.buffer = (opts && opts.shared && typeof SharedArrayBuffer === "function")
        ? new SharedArrayBuffer(bytes) : new ArrayBuffer(bytes);
    },
    Table: function () {}, Global: function () {},
    CompileError: Error, LinkError: Error, RuntimeError: Error,
  };
}
