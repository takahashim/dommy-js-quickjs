// Minimal QUnit shim to run @hotwired/stimulus's QUnit suite headless on
// Dommy + QuickJS. Registers modules/tests, then __run() executes them
// sequentially (awaiting async bodies, with a per-test scheduler timeout) and
// records pass/fail incrementally into globalThis.__qunitResults.
(function () {
  var modules = [];
  var current = null;

  function deepEqual(a, b) {
    if (a === b) return true;
    if (typeof a === "number" && typeof b === "number") return a !== a && b !== b;
    if (!a || !b || typeof a !== "object" || typeof b !== "object") return false;
    var aArr = Array.isArray(a), bArr = Array.isArray(b);
    if (aArr !== bArr) return false;
    var ka = Object.keys(a), kb = Object.keys(b);
    if (ka.length !== kb.length) return false;
    for (var i = 0; i < ka.length; i++) {
      var k = ka[i];
      if (!Object.prototype.hasOwnProperty.call(b, k)) return false;
      if (!deepEqual(a[k], b[k])) return false;
    }
    return true;
  }

  function describe(v) {
    try {
      if (typeof v === "string") return JSON.stringify(v);
      if (v && v.nodeType) return "<" + (v.tagName || v.nodeName) + ">";
      return JSON.stringify(v);
    } catch (e) { return String(v); }
  }

  function makeAssert() {
    var failures = [];
    var api = {
      __failures: failures,
      __steps: [],
      ok: function (v, m) { if (!v) failures.push((m || "ok") + ": expected truthy, got " + describe(v)); },
      notOk: function (v, m) { if (v) failures.push((m || "notOk") + ": expected falsy, got " + describe(v)); },
      true: function (v, m) { api.ok(v === true, m); },
      false: function (v, m) { api.ok(v === false, m); },
      equal: function (a, e, m) { if (a != e) failures.push((m || "equal") + ": " + describe(a) + " != " + describe(e)); },
      notEqual: function (a, e, m) { if (a == e) failures.push((m || "notEqual") + ": " + describe(a) + " == " + describe(e)); },
      strictEqual: function (a, e, m) { if (a !== e) failures.push((m || "strictEqual") + ": " + describe(a) + " !== " + describe(e)); },
      notStrictEqual: function (a, e, m) { if (a === e) failures.push((m || "notStrictEqual") + ": " + describe(a) + " === " + describe(e)); },
      deepEqual: function (a, e, m) { if (!deepEqual(a, e)) failures.push((m || "deepEqual") + ": " + describe(a) + " !deep= " + describe(e)); },
      propEqual: function (a, e, m) { api.deepEqual(a, e, m); },
      expect: function () {},
      step: function (s) { api.__steps.push(s); },
      verifySteps: function (expected, m) { api.deepEqual(api.__steps, expected, m || "verifySteps"); api.__steps = []; },
      pushResult: function (r) { if (!r.result) failures.push((r.message || "pushResult") + ": " + describe(r.actual) + " / " + describe(r.expected)); },
      async: function () { return function () {}; },
      throws: function (fn, expected, m) {
        var threw = false;
        try { fn(); } catch (e) { threw = true; }
        if (!threw) failures.push((m || "throws") + ": expected function to throw");
      }
    };
    api.raises = api.throws;
    return api;
  }

  function pushFallback() { var m = { name: "(default)", tests: [] }; modules.push(m); return m; }

  var QUnit = {
    module: function (name, fn) {
      var mod = { name: name, tests: [] };
      modules.push(mod);
      current = mod;
      if (typeof fn === "function") fn({ beforeEach: function () {}, afterEach: function () {}, before: function () {}, after: function () {} });
      current = null;
    },
    test: function (name, fn) { (current || pushFallback()).tests.push({ name: name, fn: fn, mode: "test" }); },
    skip: function (name, fn) { (current || pushFallback()).tests.push({ name: name, fn: fn, mode: "skip" }); },
    todo: function (name, fn) { (current || pushFallback()).tests.push({ name: name, fn: fn, mode: "todo" }); }
  };

  function withTimeout(promise, ms, label) {
    return Promise.race([
      Promise.resolve(promise),
      new Promise(function (_, rej) { setTimeout(function () { rej(new Error("timeout " + ms + "ms: " + label)); }, ms); })
    ]);
  }

  QUnit.__run = async function (only) {
    var results = [];
    globalThis.__qunitResults = results;
    for (var mi = 0; mi < modules.length; mi++) {
      var mod = modules[mi];
      if (only && mod.name !== only) continue;
      for (var ti = 0; ti < mod.tests.length; ti++) {
        results.push(await runOne(mod.name, mod.tests[ti]));
        globalThis.__qunitProgress = results.length;
      }
    }
    return results;
  };

  async function runOne(moduleName, t) {
    var fullName = moduleName + " :: " + t.name;
    globalThis.__qunitCurrent = fullName;
    if (t.mode === "skip") return { name: fullName, status: "skip", message: null };
    var assert = makeAssert();
    var status = "pass", message = null;
    try {
      await withTimeout(t.fn(assert), 2000, fullName);
      if (assert.__failures.length) { status = "fail"; message = assert.__failures.join(" | "); }
    } catch (e) {
      status = "fail";
      message = (e && e.stack) ? String(e.stack).split("\n").slice(0, 3).join(" ") : String(e);
    }
    if (t.mode === "todo") status = (status === "fail") ? "todo" : "todo-pass";
    return { name: fullName, status: status, message: message };
  }

  // Run exactly ONE test (by module name + test name) and record [result].
  // Used to run each test in its own freshly-created VM, so memory is fully
  // reset between tests (the bridge's handle/callback tables never evict).
  QUnit.__runOne = async function (moduleName, testName) {
    var results = [];
    globalThis.__qunitResults = results;
    for (var mi = 0; mi < modules.length; mi++) {
      var mod = modules[mi];
      if (mod.name !== moduleName) continue;
      for (var ti = 0; ti < mod.tests.length; ti++) {
        if (mod.tests[ti].name !== testName) continue;
        results.push(await runOne(mod.name, mod.tests[ti]));
        globalThis.__qunitProgress = 1;
        return results;
      }
    }
    return results;
  };

  // Every (module, test, mode) triple — the manifest a per-test runner iterates.
  QUnit.__manifest = function () {
    var out = [];
    modules.forEach(function (m) {
      m.tests.forEach(function (t) { out.push({ module: m.name, name: t.name, mode: t.mode }); });
    });
    return out;
  };

  QUnit.__modules = function () { return modules.map(function (m) { return m.name; }); };
  QUnit.__counts = function () { return { modules: modules.length, tests: modules.reduce(function (n, m) { return n + m.tests.length; }, 0) }; };
  globalThis.QUnit = QUnit;
})();
