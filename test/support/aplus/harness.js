// Promises/A+ official-suite harness for Dommy's host PromiseValue.
//
// Runs the vendored promises-aplus-tests cases inside the QuickJS realm against
// an adapter backed by __rbHost.makeHostDeferred (a host PromiseValue whose
// resolve runs the §2.3 resolution procedure). Shims the Node deps the suite
// pulls in — CommonJS `require`, `assert`, a minimal `sinon`, and mocha's
// describe/specify/before/after — and exposes `globalThis.__aplus` for the Ruby
// driver to run tests one at a time, draining the scheduler between them.
(function () {
  "use strict";
  globalThis.global = globalThis; // the suite reads `global.adapter`

  // ---- CommonJS module registry (helpers are required; test files execute) --
  var modules = {};
  function require(name) {
    var base = name.replace(/^\.\//, "").replace(/^helpers\//, "").replace(/\.js$/, "");
    if (base === "assert") return assert;
    if (base === "sinon") return sinon;
    var m = modules[base];
    if (!m) throw new Error("require: unknown module " + name);
    if (!m.loaded) { m.loaded = true; m.factory(require, m.module, m.module.exports); }
    return m.module.exports;
  }
  globalThis.__aplusRequire = require;
  globalThis.__aplusRegister = function (name, factory) {
    modules[name] = { factory: factory, module: { exports: {} }, loaded: false };
  };

  // ---- assert shim ----
  // An assertion thrown inside a `.then` reaction is swallowed by the promise,
  // so also record it on the active test's slot — the runner surfaces it instead
  // of a bare TIMEOUT.
  var activeState = null;
  function fail(message) {
    if (activeState && !activeState.asyncError) activeState.asyncError = message;
    throw new Error(message);
  }
  function str(v) { try { return typeof v === "object" && v ? "[object]" : String(v); } catch (e) { return "?"; } }
  // `assert(value, msg)` is itself callable (truthiness check) and also carries
  // strictEqual / notStrictEqual — matching Node's assert module.
  function assert(value, msg) { if (!value) fail("assert: " + (msg || "falsy")); }
  assert.strictEqual = function (a, b, msg) { if (a !== b) fail("strictEqual: " + (msg || "") + " got " + str(a) + " want " + str(b)); };
  assert.notStrictEqual = function (a, b, msg) { if (a === b) fail("notStrictEqual: " + (msg || "")); };

  // ---- minimal sinon (used only by 2.2.6) ----
  var callSeq = 0;
  function tracker(impl) {
    var fn = function () {
      fn.callCount++;
      fn.calls.push({ args: Array.prototype.slice.call(arguments), order: ++callSeq });
      if (fn.__throw) throw fn.__throwValue;
      return impl ? impl.apply(this, arguments) : fn.__return;
    };
    fn.callCount = 0; fn.calls = []; fn.__isSpy = true;
    fn.returns = function (v) { fn.__return = v; return fn; };
    fn.throws = function (v) { fn.__throw = true; fn.__throwValue = v; return fn; };
    return fn;
  }
  var sinon = {
    spy: function (impl) { return tracker(typeof impl === "function" ? impl : null); },
    stub: function () { return tracker(null); },
    match: { same: function (x) { return { __match: true, test: function (v) { return v === x; }, x: x }; } },
    assert: {
      calledWith: function (fn, matcher) {
        var ok = fn.calls.some(function (c) { return c.args.length && (matcher && matcher.__match ? matcher.test(c.args[0]) : c.args[0] === matcher); });
        if (!ok) fail("sinon.calledWith failed");
      },
      notCalled: function (fn) { if (fn.callCount !== 0) fail("sinon.notCalled failed"); },
      callOrder: function () {
        var fns = Array.prototype.slice.call(arguments);
        var orders = fns.map(function (f) { return f.calls.length ? f.calls[0].order : -1; });
        for (var i = 1; i < orders.length; i++) if (!(orders[i - 1] < orders[i])) fail("sinon.callOrder failed (" + orders.join(",") + ")");
      }
    }
  };

  // ---- mocha shim ----
  var root = newSuite("", null);
  var current = root;
  function newSuite(name, parent) { return { name: name, parent: parent, tests: [], suites: [], before: [], after: [], beforeEach: [], afterEach: [] }; }
  var ctx = { timeout: function () {}, slow: function () {} };
  globalThis.describe = function (name, fn) { var s = newSuite(name, current); current.suites.push(s); var prev = current; current = s; fn.call(ctx); current = prev; };
  globalThis.specify = globalThis.it = function (name, fn) { current.tests.push({ name: name, fn: fn, suite: current }); };
  globalThis.before = function (fn) { current.before.push(fn); };
  globalThis.after = function (fn) { current.after.push(fn); };
  globalThis.beforeEach = function (fn) { current.beforeEach.push(fn); };
  globalThis.afterEach = function (fn) { current.afterEach.push(fn); };

  // ---- adapter (host PromiseValue) ----
  globalThis.adapter = {
    deferred: function () { return __rbHost.makeHostDeferred(); },
    resolved: function (v) { var d = __rbHost.makeHostDeferred(); d.resolve(v); return d.promise; },
    rejected: function (r) { var d = __rbHost.makeHostDeferred(); d.reject(r); return d.promise; }
  };

  // ---- runner (driven from Ruby) ----
  var flat = null, state = [], prevPath = [];
  function pathOf(suite) { var p = []; for (var s = suite; s; s = s.parent) p.unshift(s); return p; }
  function collect() {
    flat = [];
    (function walk(s) { s.tests.forEach(function (t) { flat.push(t); }); s.suites.forEach(walk); })(root);
    return flat.length;
  }
  globalThis.__aplus = {
    collect: collect,
    name: function (i) { return pathOf(flat[i].suite).map(function (s) { return s.name; }).filter(Boolean).join(" / ") + " :: " + flat[i].name; },
    start: function (i) {
      var test = flat[i], path = pathOf(test.suite);
      var st = { finished: false, error: null, asyncError: null };
      state[i] = st;
      activeState = st;
      try {
        // suite before/after at boundaries (vs the previous test's path)
        for (var k = prevPath.length - 1; k >= 0; k--) if (path.indexOf(prevPath[k]) === -1) prevPath[k].after.forEach(function (h) { h(); });
        for (var k2 = 0; k2 < path.length; k2++) if (prevPath.indexOf(path[k2]) === -1) path[k2].before.forEach(function (h) { h(); });
        prevPath = path;
        path.forEach(function (s) { s.beforeEach.forEach(function (h) { h.call(ctx); }); });
        var afterEachAll = function () { for (var k3 = path.length - 1; k3 >= 0; k3--) path[k3].afterEach.forEach(function (h) { h.call(ctx); }); };
        if (test.fn.length >= 1) {
          var done = function (err) { if (st.finished) return; if (err) st.error = err; try { afterEachAll(); } catch (e) { st.error = st.error || e; } st.finished = true; };
          test.fn.call(ctx, done);
        } else {
          test.fn.call(ctx); afterEachAll(); st.finished = true;
        }
      } catch (e) { st.error = e; st.finished = true; }
    },
    result: function (i) {
      var st = state[i] || { finished: false, error: null, asyncError: null };
      var err = st.error ? (st.error.message || String(st.error)) : st.asyncError;
      return { finished: !!st.finished, error: err || null };
    }
  };
})();
