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

  // 2a: array-like DOM collections that cross as proxies (not as JS arrays the
  // way NodeList does) need Symbol.iterator so for-of / spread work. They expose
  // length + integer indices through the ABI, so the iterator walks those.
  const ARRAY_LIKE_COLLECTIONS = new Set([
    "HTMLCollection", "NodeList", "DOMTokenList", "NamedNodeMap", "DOMStringList",
    "FileList", "CSSRuleList", "StyleSheetList", "DataTransferItemList"
  ]);
  // Map-like collections iterated as [key, value] pairs via .entries().
  const ENTRIES_ITERABLES = new Set(["URLSearchParams", "FormData", "Headers"]);

  // WebIDL [Constant]s exposed on Node (and inherited by every node interface):
  // the nodeType values plus the compareDocumentPosition bit flags.
  const NODE_CONSTANTS = {
    ELEMENT_NODE: 1, ATTRIBUTE_NODE: 2, TEXT_NODE: 3, CDATA_SECTION_NODE: 4,
    ENTITY_REFERENCE_NODE: 5, ENTITY_NODE: 6, PROCESSING_INSTRUCTION_NODE: 7,
    COMMENT_NODE: 8, DOCUMENT_NODE: 9, DOCUMENT_TYPE_NODE: 10,
    DOCUMENT_FRAGMENT_NODE: 11, NOTATION_NODE: 12,
    DOCUMENT_POSITION_DISCONNECTED: 1, DOCUMENT_POSITION_PRECEDING: 2,
    DOCUMENT_POSITION_FOLLOWING: 4, DOCUMENT_POSITION_CONTAINS: 8,
    DOCUMENT_POSITION_CONTAINED_BY: 16, DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC: 32
  };

  // WebIDL [Constant]s exposed on the Event interface object + prototype.
  const EVENT_CONSTANTS = {
    NONE: 0, CAPTURING_PHASE: 1, AT_TARGET: 2, BUBBLING_PHASE: 3
  };

  // Interface name -> its [Constant]s (placed on both the interface object and
  // its prototype; instances inherit via the proxy get `prop in target` path).
  const INTERFACE_CONSTANTS = { Node: NODE_CONSTANTS, Event: EVENT_CONSTANTS };

  // 1d: custom elements. ceRegistry maps a tag name to its JS constructor;
  // constructionStack carries the element being upgraded so the interface base
  // constructor (see protoForChain) adopts it when `super()` runs; cePending
  // holds whenDefined() resolvers waiting for a name to be defined.
  const ceRegistry = new Map();
  const constructionStack = [];
  const cePending = new Map();

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

  // The set of property names a prototype chain exposes via accessor setters
  // (a framework's reactive properties, e.g. Lit), computed once per prototype
  // and cached — so the set trap doesn't walk the chain on every write.
  const setterPropsCache = new WeakMap();
  function settersOf(proto) {
    let names = setterPropsCache.get(proto);
    if (names) return names;
    names = new Set();
    for (let o = proto; o && o !== Object.prototype; o = Object.getPrototypeOf(o)) {
      const descs = Object.getOwnPropertyDescriptors(o);
      for (const k of Object.keys(descs)) {
        if (typeof descs[k].set === "function") names.add(k);
      }
    }
    setterPropsCache.set(proto, names);
    return names;
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

  // Dehydrate a top-level call/constructor argument list, tagging an explicit
  // `undefined` so it crosses as Dommy::Bridge::UNDEFINED (distinct from the
  // `nil` a JS `null` becomes) — letting WebIDL-style dispatch tell an omitted
  // optional argument from an explicit null. Only top-level args are tagged;
  // `undefined` nested inside an object still dehydrates to null, preserving
  // existing option-bag behavior.
  function dehydrateArgs(args) {
    return Array.prototype.map.call(args, (a) => (a === undefined ? { __rb_undefined: true } : dehydrate(a)));
  }

  // A host call that raised a Dommy::DOMException comes back tagged so it can be
  // re-thrown JS-side as a real DOMException (name + legacy code, and
  // `instanceof DOMException`). Without this the quickjs gem flattens it to a
  // plain Error, breaking assert_throws_dom and the DOM's error contracts.
  function makeHostError(info) {
    const G = globalThis;
    if (typeof G.DOMException === "function") {
      try {
        return new G.DOMException(info.message, info.name);
      } catch (_) {
        /* fall through to a plain Error */
      }
    }
    const e = new Error(info.message);
    if (info.name) e.name = info.name;
    if (info.code !== undefined && info.code !== null) e.code = info.code;
    return e;
  }

  function rehydrate(v) {
    if (Array.isArray(v)) return v.map(rehydrate);
    if (v !== null && typeof v === "object") {
      if (v.__rb_exception__) throw makeHostError(v.__rb_exception__);
      // A void DOM op marshals as this marker so it becomes `undefined`, not the
      // `null` a bare Ruby nil would (e.g. DOMTokenList add/remove return undefined).
      if (v.__rb_undefined) return undefined;
      if ("__rb_handle" in v) return makeProxy(v.__rb_handle);
      // Symmetric with dehydrate: a tagged callback restores to the live JS
      // function it was registered from (so functions nested in objects — e.g.
      // an event's detail — survive a round trip through Ruby).
      if ("__rb_callback" in v) {
        const fn = callbacks.get(v.__rb_callback);
        if (fn) return fn;
      }
      const out = {};
      for (const k of Object.keys(v)) out[k] = rehydrate(v[k]);
      return out;
    }
    return v;
  }

  // ===== DOM interface prototypes & constructors (1a/1b/1c) =====

  // 1c: build a host object from a bare interface constructor
  // (new Event(...) / new DOMException(...)). Ruby resolves the named
  // constructor by interface name; null means "not constructable" so we throw.
  function constructInterface(name, args) {
    const r = rehydrate(__rb_construct(name, dehydrateArgs(args)));
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
  // 2d: method name sets are per-interface (class), so cache them by interface
  // name and reuse across every proxy of that interface instead of rebuilding.
  const methodsByInterface = new Map();
  function protoForChain(chain, i) {
    const name = chain[i];
    const cached = protos.get(name);
    if (cached) return cached;
    const parent = (i + 1 < chain.length) ? protoForChain(chain, i + 1) : Object.prototype;
    const proto = Object.create(parent);
    Object.defineProperty(proto, Symbol.toStringTag, { value: name, configurable: true });
    // Only node/element constructors adopt an element being upgraded. Otherwise
    // a non-element `new` (e.g. `new IntersectionObserver()` inside a custom
    // element's constructor) would greedily adopt the queued element off the
    // shared construction stack and hijack its prototype.
    const consultsStack = chain.includes("Node");
    const ctor = function (...args) {
      const nt = new.target;
      if (nt === undefined) throw new TypeError(name + " requires 'new'");
      // 1d: custom element upgrade — when a construction is queued, `super()`
      // adopts the element being upgraded (its proxy) and stamps it with the
      // derived class's prototype, rather than minting a new backing object.
      if (consultsStack && constructionStack.length > 0) {
        const el = constructionStack[constructionStack.length - 1];
        Object.setPrototypeOf(el, nt.prototype);
        return el;
      }
      return constructInterface(name, args);
    };
    Object.defineProperty(ctor, "name", { value: name, configurable: true });
    ctor.prototype = proto;
    Object.defineProperty(proto, "constructor", { value: ctor, configurable: true, writable: true });
    // WebIDL [Constant]s live on both the interface object and its prototype
    // (so `Node.ELEMENT_NODE`, `el.ELEMENT_NODE`, `Event.CAPTURING_PHASE`, …
    // all === the numeric value). Instances reach the prototype copy via the
    // proxy get trap's `prop in target` fallback.
    const constants = INTERFACE_CONSTANTS[name];
    if (constants) {
      for (const [k, val] of Object.entries(constants)) {
        const desc = { value: val, enumerable: true, writable: false, configurable: false };
        Object.defineProperty(proto, k, desc);
        Object.defineProperty(ctor, k, desc);
      }
    }
    if (ARRAY_LIKE_COLLECTIONS.has(name)) {
      Object.defineProperty(proto, Symbol.iterator, {
        value: function () {
          let i = 0;
          const self = this;
          return { next: () => (i < self.length ? { value: self[i++], done: false } : { value: undefined, done: true }) };
        },
        configurable: true, writable: true
      });
    } else if (ENTRIES_ITERABLES.has(name)) {
      Object.defineProperty(proto, Symbol.iterator, {
        value: function () { return this.entries()[Symbol.iterator](); },
        configurable: true, writable: true
      });
    }
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

  // 1c: expose an interface constructor's static/class methods (URL.createObjectURL,
  // URL.parse, …) on the seeded global, delegating to the window's constructor.
  // Called once the window is bound (statics live on the window's constructors).
  function attachStatics() {
    for (const name of protos.keys()) {
      const ctor = globalThis[name];
      if (typeof ctor !== "function") continue;
      for (const m of __rb_static_names(name)) {
        if (m in ctor) continue;
        ctor[m] = (...args) => rehydrate(__rb_static_call(name, m, dehydrateArgs(args)));
      }
    }
  }

  // Expose the interface constructors as own properties of the `window` proxy
  // so `window.Node` / `document.defaultView.DOMException` / … resolve to the
  // same constructor functions as the bare globals. In a browser window IS the
  // global object; here it's a separate host proxy whose host get returns null
  // for these, which broke e.g. assert_throws_dom(type, doc.defaultView.DOMException, …)
  // (it read `.name` off null). Defining them on the proxy target means the get
  // trap's own-property fast path returns the real function with no round trip.
  function exposeConstructorsOnWindow() {
    const w = globalThis.window;
    if (!w) return;
    const names = [...protos.keys()];
    if (typeof globalThis.DOMException === "function") names.push("DOMException");
    for (const name of names) {
      const ctor = globalThis[name];
      if (typeof ctor !== "function") continue;
      try {
        // Only fill in names the window doesn't already resolve (host-backed
        // constructors like Event keep their existing object).
        if (w[name] == null) {
          Object.defineProperty(w, name, { value: ctor, configurable: true, writable: true });
        }
      } catch (e) { /* non-configurable / frozen — leave as-is */ }
    }
  }

  // ===== Host object proxy =====

  // The proxy traps route each access to one of the bridge's layers. The order
  // is deliberate — changing it breaks subtle cases, so it's spelled out here:
  //
  //   get(prop):
  //     1. HKEY symbol             -> the Ruby handle (identity tag)
  //     2. any other symbol        -> target/prototype (Symbol.toStringTag/iterator)
  //     3. own property on target  -> a JS-side expando (object identity intact)
  //     4. ABI method name         -> a per-proxy memoized fn (__rb_host_call)
  //     5. ABI property (non-null) -> the __rb_host_get value
  //     6. prototype member        -> constructor / connectedCallback / etc.
  //
  //   set(prop, value):
  //     1. symbol                  -> store on the target
  //     2. prototype setter        -> run it (framework reactive props, e.g. Lit)
  //     3. Dommy handled it        -> a DOM property write
  //     4. otherwise               -> a JS-side expando on the target
  function makeHandler(handle, methods, methodCache) {
    return {
      get(t, prop, receiver) {
        if (prop === HKEY) return handle;
        if (typeof prop === "symbol") return Reflect.get(t, prop, receiver);
        if (Object.hasOwn(t, prop)) return Reflect.get(t, prop, receiver);
        if (methods.has(prop)) {
          let fn = methodCache.get(prop);
          if (!fn) {
            fn = (...args) => rehydrate(__rb_host_call(handle, prop, dehydrateArgs(args)));
            methodCache.set(prop, fn);
          }
          return fn;
        }
        const v = rehydrate(__rb_host_get(handle, prop));
        if (v == null && (prop in t)) return Reflect.get(t, prop, receiver);
        return v;
      },
      set(t, prop, value, receiver) {
        if (typeof prop === "symbol") { t[prop] = value; return true; }
        if (settersOf(Object.getPrototypeOf(t)).has(prop)) {
          Reflect.set(t, prop, value, receiver);
          return true;
        }
        if (!__rb_host_set(handle, prop, dehydrate(value))) t[prop] = value;
        return true;
      },
      has() { return true; }
    };
  }

  function makeProxy(handle) {
    const ref = cache.get(handle);
    if (ref) {
      const existing = ref.deref();
      if (existing) return existing;
    }
    // 2d: one host round trip describes the node (interface + methods + ce).
    const desc = __rb_host_describe(handle);
    // 2d: method-name sets are per-interface; reuse across proxies of that type.
    let methods = methodsByInterface.get(desc.name);
    if (!methods) {
      methods = new Set(desc.methods);
      methodsByInterface.set(desc.name, methods);
    }
    const target = (desc.chain && desc.chain.length)
      ? Object.create(protoForChain(desc.chain, 0))
      : {};
    // 2c: memoize method functions per proxy so `el.foo === el.foo`.
    const p = new Proxy(target, makeHandler(handle, methods, new Map()));
    cache.set(handle, new WeakRef(p));
    finalizers.register(p, handle);
    // 1d: a Dommy-registered custom element node is upgraded to its JS class on
    // first crossing — so the constructor runs before any lifecycle callback.
    if (desc.ce) upgradeElement(p, desc.ce);
    return p;
  }

  // ===== Custom elements (1d) =====

  // Run a JS custom element's constructor against an existing Dommy-backed proxy
  // (the construction-stack adoption proven by the Step 0 spike), making the
  // proxy an instance of the registered class with its constructor side effects.
  function upgradeElement(proxy, name) {
    const ctor = ceRegistry.get(name);
    if (!ctor) return;
    constructionStack.push(proxy);
    try { Reflect.construct(ctor, [], ctor); }
    finally { constructionStack.pop(); }
  }

  // Ruby calls this when a registered custom element fires a lifecycle reaction.
  // makeProxy upgrades on first crossing, so the constructor has already run.
  function invokeLifecycle(handle, callback, args) {
    const p = makeProxy(handle);
    const fn = p[callback];
    if (typeof fn !== "function") return undefined;
    return dehydrate(fn.apply(p, rehydrate(args || [])));
  }

  // customElements.define(name, JSClass): register JS-side and ask Ruby to wire
  // a Dommy custom element whose reactions route back through invokeLifecycle.
  function defineCustomElement(name, ctor) {
    ceRegistry.set(name, ctor);
    const observed = Array.isArray(ctor.observedAttributes) ? ctor.observedAttributes : [];
    __rb_define_custom_element(name, observed);
    const waiters = cePending.get(name);
    if (waiters) { cePending.delete(name); waiters.forEach((resolve) => resolve(ctor)); }
  }

  // whenDefined stays pending until the name is defined (spec semantics), so
  // `await customElements.whenDefined(x)` before define() doesn't resolve early.
  function whenDefinedCustomElement(name) {
    const ctor = ceRegistry.get(name);
    if (ctor) return Promise.resolve(ctor);
    return new Promise((resolve) => {
      if (!cePending.has(name)) cePending.set(name, []);
      cePending.get(name).push(resolve);
    });
  }

  globalThis.customElements = {
    define: (name, ctor) => defineCustomElement(name, ctor),
    get: (name) => ceRegistry.get(name),
    whenDefined: (name) => whenDefinedCustomElement(name),
    // Delegate manual upgrades to Dommy's registry (define() already upgrades
    // existing nodes; this covers subtrees attached without reactions).
    upgrade: (root) => { if (isProxy(root)) __rb_upgrade_custom_elements(root[HKEY]); }
  };

  // 1a: report the DOM interface chain of a host proxy, most-derived first
  // (e.g. ["HTMLDivElement","HTMLElement","Element","Node","EventTarget"]).
  // Returns null for non-proxies.
  function interfaceOf(proxy) {
    if (!isProxy(proxy)) return null;
    return __rb_host_describe(proxy[HKEY]);
  }

  return { makeProxy, invokeCallback, tag: dehydrate, interfaceOf, seedInterfaces, invokeLifecycle, attachStatics, exposeConstructorsOnWindow };
})();
