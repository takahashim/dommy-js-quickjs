// JS half of the Dommy <-> Ruby DOM bridge. Loaded once per backend and
// eval'd into the VM. Defines globalThis.__rbHost.{makeProxy, invokeCallback,
// tag, interfaceOf, seedInterfaces}.
//
// Values crossing the boundary are tagged: a bridge-able Ruby object is
// `{ __rb_handle: id }`, a JS function passed to Ruby is `{ __rb_callback: id }`.
globalThis.__rbHost = (function () {
  const HKEY = Symbol("rbHandle");
  const cache = new Map();            // handle -> WeakRef(proxy)
  const callbacks = new Map();
  const callbackIds = new WeakMap();
  let nextCb = 1;

  // When a proxy is garbage-collected, drop the Ruby-side handle entry
  // (unless a live re-proxy for the same handle exists). Keeps the
  // registry bounded on long-lived VMs. Handles are monotonic on the
  // Ruby side, so a handle never refers to two different objects.
  const finalizers = new FinalizationRegistry((handle) => {
    const ref = cache.get(handle);
    if (!ref || ref.deref() === undefined) {
      cache.delete(handle);
      __rb_release_handle(handle);
    }
  });

  function isProxy(v) {
    return v !== null && typeof v === "object" && v[HKEY] !== undefined;
  }

  // Same function -> same id, so addEventListener / removeEventListener
  // round-trip to the same Ruby HostCallback (Dommy matches by identity).
  function registerCallback(fn) {
    if (callbackIds.has(fn)) return callbackIds.get(fn);
    const id = nextCb++;
    callbacks.set(id, fn);
    callbackIds.set(fn, id);
    return id;
  }

  // Called from Ruby when a host event dispatch reaches a JS-registered
  // listener. The live function (closure intact) is invoked; tagged args
  // (e.g. an Event handle) are rehydrated to proxies first.
  function invokeCallback(id, args) {
    const fn = callbacks.get(id);
    if (!fn) return undefined;
    return dehydrate(fn.apply(undefined, rehydrate(args || [])));
  }

  function dehydrate(v, seen) {
    if (typeof v === "function") return { __rb_callback: registerCallback(v) };
    if (isProxy(v)) return { __rb_handle: v[HKEY] };
    if (v !== null && typeof v === "object") {
      seen = seen || new WeakSet();
      if (seen.has(v)) return undefined; // break reference cycles
      seen.add(v);
      if (Array.isArray(v)) return v.map((e) => dehydrate(e, seen));
      const out = {};
      for (const k of Object.keys(v)) out[k] = dehydrate(v[k], seen);
      return out;
    }
    return v;
  }

  function rehydrate(v) {
    if (Array.isArray(v)) return v.map(rehydrate);
    if (v !== null && typeof v === "object") {
      if ("__rb_handle" in v) return makeProxy(v.__rb_handle);
      const out = {};
      for (const k of Object.keys(v)) out[k] = rehydrate(v[k]);
      return out;
    }
    return v;
  }

  // 1c: build a host object from a bare interface constructor
  // (new Event(...) / new DOMException(...)). Ruby resolves the named
  // constructor by interface name; null means "not constructable" so we throw.
  function constructInterface(name, args) {
    const r = rehydrate(__rb_construct(name, dehydrate(args)));
    if (r == null) throw new TypeError("Illegal constructor");
    return r;
  }

  // 1b: lazily build a JS prototype chain + constructor per DOM interface,
  // mirroring the chain Ruby reports (most-derived first). Cached by name so the
  // shared tail (…Element→Node→EventTarget) is built once and every node links
  // into the same prototypes — making `instanceof` and Object.prototype.toString
  // (via Symbol.toStringTag) work. Constructable interfaces (Event, DOMException,
  // …) build via Ruby; the rest throw Illegal constructor (HTMLElement until 1d).
  const protos = new Map();
  function protoForChain(chain, i) {
    const name = chain[i];
    const cached = protos.get(name);
    if (cached) return cached;
    const parent = (i + 1 < chain.length) ? protoForChain(chain, i + 1) : Object.prototype;
    const proto = Object.create(parent);
    Object.defineProperty(proto, Symbol.toStringTag, { value: name, configurable: true });
    const ctor = function (...args) {
      if (new.target === undefined) throw new TypeError(name + " requires 'new'");
      return constructInterface(name, args);
    };
    Object.defineProperty(ctor, "name", { value: name, configurable: true });
    ctor.prototype = proto;
    Object.defineProperty(proto, "constructor", { value: ctor, configurable: true, writable: true });
    if (!(name in globalThis)) globalThis[name] = ctor;
    protos.set(name, proto);
    return proto;
  }

  // Eagerly build the base interfaces (chains supplied by Ruby, the single
  // source of hierarchy knowledge) so `instanceof Node` / `typeof HTMLElement`
  // resolve before an instance of that exact type has crossed.
  function seedInterfaces(chains) {
    chains.forEach((c) => protoForChain(c, 0));
  }

  function makeProxy(handle) {
    const ref = cache.get(handle);
    if (ref) {
      const existing = ref.deref();
      if (existing) return existing;
    }
    const methods = new Set(__rb_host_methods(handle));
    const info = __rb_host_interface(handle);
    const target = (info && info.chain && info.chain.length)
      ? Object.create(protoForChain(info.chain, 0))
      : {};
    const p = new Proxy(target, {
      get(t, prop, receiver) {
        if (prop === HKEY) return handle;
        // Let symbols (Symbol.toStringTag, and future Symbol.iterator)
        // resolve through the interface prototype instead of vanishing.
        if (typeof prop === "symbol") return Reflect.get(t, prop, receiver);
        if (methods.has(prop)) {
          return function (...args) {
            return rehydrate(__rb_host_call(handle, prop, dehydrate(args)));
          };
        }
        const v = rehydrate(__rb_host_get(handle, prop));
        // Fall back to the interface prototype for JS-intrinsic members
        // (constructor, Object.prototype.*) the DOM ABI doesn't provide.
        if (v == null && (prop in t)) return Reflect.get(t, prop, receiver);
        return v;
      },
      set(_t, prop, value) {
        if (typeof prop !== "symbol") {
          __rb_host_set(handle, prop, dehydrate(value));
        }
        return true;
      },
      has() { return true; }
    });
    cache.set(handle, new WeakRef(p));
    finalizers.register(p, handle);
    return p;
  }

  // 1a: report the DOM interface chain of a host proxy, most-derived first
  // (e.g. ["HTMLDivElement","HTMLElement","Element","Node","EventTarget"]).
  // Returns null for non-proxies.
  function interfaceOf(proxy) {
    if (!isProxy(proxy)) return null;
    return __rb_host_interface(proxy[HKEY]);
  }

  return { makeProxy, invokeCallback, tag: dehydrate, interfaceOf, seedInterfaces };
})();
