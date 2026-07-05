// Minimal mocha (TDD interface) + chai `assert` shim to run @hotwired/turbo's
// unit suite headless on Dommy + QuickJS — the Turbo analogue of qunit_shim.js.
//
// Turbo's unit tests use mocha's TDD globals (`suite`/`test`/`setup`/`teardown`)
// and import `{ assert }` from "@open-wc/testing" (chai's assert interface).
// Unlike QUnit, `assert` is a MODULE SINGLETON shared by every test rather than
// a per-test argument, so its methods record into a mutable `activeFailures`
// that the runner swaps before each test.
//
// Grouping: Turbo's unit files don't wrap tests in `suite()`, so the build
// script prepends `__setModule("<file>")` to each unit file — that name becomes
// the "module" for per-file reporting, mirroring the Stimulus runner's modules.
//
// Operational API mirrors qunit_shim's: `Mocha.__manifest()` /
// `Mocha.__runOne(module, test)` writing into `globalThis.__mochaResults`, so
// test/support/turbo_conformance.rb reuses the Stimulus runner logic verbatim.
(function () {
  var modules = [];
  var current = null; // module being registered into
  var activeFailures = null; // set by runOne per test; assert methods push here

  function fail(m) { if (activeFailures) activeFailures.push(m); }

  function describe(v) {
    try {
      if (typeof v === "string") return JSON.stringify(v);
      if (v && v.nodeType) return "<" + (v.tagName || v.nodeName) + ">";
      return JSON.stringify(v);
    } catch (e) { return String(v); }
  }

  function deepEqual(a, b) {
    if (a === b) return true;
    if (typeof a === "number" && typeof b === "number") return a !== a && b !== b;
    if (!a || !b || typeof a !== "object" || typeof b !== "object") return false;
    var ka = Object.keys(a), kb = Object.keys(b);
    if (ka.length !== kb.length) return false;
    for (var i = 0; i < ka.length; i++) {
      if (!Object.prototype.hasOwnProperty.call(b, ka[i])) return false;
      if (!deepEqual(a[ka[i]], b[ka[i]])) return false;
    }
    return true;
  }

  // chai's `include`: Set/Map membership, array/string containment, or object
  // property-subset — matching how Turbo's unit tests use it (LimitedSet.has).
  function includes(haystack, needle) {
    if (haystack == null) return false;
    if (typeof haystack.has === "function") return haystack.has(needle);
    if (typeof haystack.indexOf === "function") return haystack.indexOf(needle) >= 0;
    if (typeof haystack === "object" && needle && typeof needle === "object") {
      for (var k in needle) { if (haystack[k] !== needle[k]) return false; }
      return true;
    }
    return false;
  }

  // chai `assert` — the subset Turbo's unit tests use, plus a few obvious
  // neighbours so a Turbo version bump is unlikely to hit a missing method.
  var assert = {
    equal: function (a, e, m) { if (a != e) fail((m || "equal") + ": " + describe(a) + " != " + describe(e)); },
    notEqual: function (a, e, m) { if (a == e) fail((m || "notEqual") + ": " + describe(a) + " == " + describe(e)); },
    strictEqual: function (a, e, m) { if (a !== e) fail((m || "strictEqual") + ": " + describe(a) + " !== " + describe(e)); },
    notStrictEqual: function (a, e, m) { if (a === e) fail((m || "notStrictEqual") + ": " + describe(a) + " === " + describe(e)); },
    deepEqual: function (a, e, m) { if (!deepEqual(a, e)) fail((m || "deepEqual") + ": " + describe(a) + " !deep= " + describe(e)); },
    ok: function (v, m) { if (!v) fail((m || "ok") + ": expected truthy, got " + describe(v)); },
    isOk: function (v, m) { assert.ok(v, m); },
    notOk: function (v, m) { if (v) fail((m || "notOk") + ": expected falsy, got " + describe(v)); },
    isNotOk: function (v, m) { assert.notOk(v, m); },
    isTrue: function (v, m) { if (v !== true) fail((m || "isTrue") + ": expected true, got " + describe(v)); },
    isFalse: function (v, m) { if (v !== false) fail((m || "isFalse") + ": expected false, got " + describe(v)); },
    isNull: function (v, m) { if (v !== null) fail((m || "isNull") + ": expected null, got " + describe(v)); },
    isNotNull: function (v, m) { if (v === null) fail((m || "isNotNull") + ": expected non-null"); },
    isUndefined: function (v, m) { if (v !== undefined) fail((m || "isUndefined") + ": expected undefined, got " + describe(v)); },
    isDefined: function (v, m) { if (v === undefined) fail((m || "isDefined") + ": expected defined"); },
    exists: function (v, m) { if (v == null) fail((m || "exists") + ": expected non-null/undefined"); },
    include: function (h, n, m) { if (!includes(h, n)) fail((m || "include") + ": " + describe(h) + " lacks " + describe(n)); },
    notInclude: function (h, n, m) { if (includes(h, n)) fail((m || "notInclude") + ": " + describe(h) + " includes " + describe(n)); },
    instanceOf: function (v, t, m) { if (!(v instanceof t)) fail((m || "instanceOf") + ": not an instance of " + (t && t.name)); },
    lengthOf: function (v, n, m) { if (!v || v.length !== n) fail((m || "lengthOf") + ": expected length " + n + ", got " + (v && v.length)); },
    throws: function (fn, _e, m) {
      var threw = false;
      try { fn(); } catch (e) { threw = true; }
      if (!threw) fail((m || "throws") + ": expected function to throw");
    }
  };
  globalThis.__assert = assert;

  function pushModule(name) { var mod = { name: name, setups: [], teardowns: [], tests: [] }; modules.push(mod); current = mod; return mod; }
  function ensure() { return current || pushModule("(default)"); }

  // Called by the build-script-injected marker at the top of each unit file.
  globalThis.__setModule = function (name) { pushModule(name); };

  // mocha TDD globals. Turbo's unit files call test/setup at top level; suite()
  // is supported for completeness (restores the prior module afterwards).
  globalThis.suite = function (name, fn) { var prev = current; pushModule(name); if (typeof fn === "function") fn(); current = prev; };
  globalThis.test = function (name, fn) { ensure().tests.push({ name: name, fn: fn }); };
  globalThis.setup = function (fn) { ensure().setups.push(fn); };
  globalThis.teardown = function (fn) { ensure().teardowns.push(fn); };
  globalThis.suiteSetup = function (fn) { ensure().setups.push(fn); };
  globalThis.suiteTeardown = function (fn) { ensure().teardowns.push(fn); };

  function withTimeout(promise, ms, label) {
    return Promise.race([
      Promise.resolve(promise),
      new Promise(function (_, rej) { setTimeout(function () { rej(new Error("timeout " + ms + "ms: " + label)); }, ms); })
    ]);
  }

  async function runOne(mod, t) {
    var fullName = mod.name + " :: " + t.name;
    var failures = [];
    activeFailures = failures;
    var status = "pass", message = null;
    try {
      for (var i = 0; i < mod.setups.length; i++) await withTimeout(mod.setups[i](), 2000, fullName + " (setup)");
      await withTimeout(t.fn(), 2000, fullName);
      for (var j = 0; j < mod.teardowns.length; j++) await withTimeout(mod.teardowns[j](), 2000, fullName + " (teardown)");
      if (failures.length) { status = "fail"; message = failures.join(" | "); }
    } catch (e) {
      status = "fail";
      message = (e && e.stack) ? String(e.stack).split("\n").slice(0, 3).join(" ") : String(e);
    }
    activeFailures = null;
    return { name: fullName, status: status, message: message };
  }

  var Mocha = {
    // Run exactly ONE test (module name + test name) in the current VM and
    // record [result] — one test per freshly-created VM, so memory is fully
    // reset between tests (the bridge's handle/callback tables never evict).
    __runOne: async function (moduleName, testName) {
      var results = [];
      globalThis.__mochaResults = results;
      for (var mi = 0; mi < modules.length; mi++) {
        var mod = modules[mi];
        if (mod.name !== moduleName) continue;
        for (var ti = 0; ti < mod.tests.length; ti++) {
          if (mod.tests[ti].name !== testName) continue;
          results.push(await runOne(mod, mod.tests[ti]));
          return results;
        }
      }
      return results;
    },
    // Every (module, test) pair — the manifest a per-test runner iterates.
    __manifest: function () {
      var out = [];
      modules.forEach(function (m) {
        m.tests.forEach(function (t) { out.push({ module: m.name, name: t.name, mode: "test" }); });
      });
      return out;
    },
    __modules: function () { return modules.map(function (m) { return m.name; }); },
    __counts: function () { return { modules: modules.length, tests: modules.reduce(function (n, m) { return n + m.tests.length; }, 0) }; }
  };
  globalThis.Mocha = Mocha;
})();
