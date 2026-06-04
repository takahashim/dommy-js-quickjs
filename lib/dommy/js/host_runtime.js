// JS half of the Dommy <-> Ruby DOM bridge. Loaded once per backend and
// eval'd into the VM. Defines globalThis.__rbHost.{makeProxy, invokeCallback,
// tag, interfaceOf, seedInterfaces}.
//
// Values crossing the boundary are tagged: a bridge-able Ruby object is
// `{ __rb_handle: id }`, a JS function passed to Ruby is `{ __rb_callback: id }`.
globalThis.__rbHost = (function () {
  const HKEY = Symbol("rbHandle");
  const cache = new Map();            // handle -> WeakRef(proxy)
  // proxy -> handle, by object identity. Used to recognise our own proxies
  // WITHOUT reading a property off the candidate: probing `v[HKEY]` would fire
  // the get trap of a *foreign* proxy (e.g. a Vue/Alpine `reactive()` Proxy),
  // and because HKEY is a non-well-known symbol, Vue's reactivity tracks it as a
  // dependency. That stray symbol key then poisons the array's dep map, so a
  // later length-shrinking mutation (pop/shift/splice) does `symbol >= newLen`
  // and throws "cannot convert symbol to number". A WeakMap lookup is pure.
  const proxyHandles = new WeakMap(); // proxy -> handle (identity, trap-free)
  // handle -> proxy, STRONG. A proxy is normally cached only weakly (so it can
  // be GC'd and its Ruby handle released), but once JS code stores an expando on
  // it — framework bookkeeping like lit-html's `_$litPart$` or React's
  // `__reactFiber$…` — that state must survive as long as the node is reachable,
  // exactly as in a browser. We therefore pin the proxy here so a later access
  // (e.g. the next `getElementById` + render) returns the SAME proxy with its
  // expandos intact, rather than a fresh proxy that lost them to GC.
  const pinned = new Map();
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

  // Array-like collections that are iterable ONLY via @@iterator (their IDL is
  // not declared `iterable<>`, so they lack keys()/values()/entries()/forEach()).
  const INDEXED_ONLY_ITERABLE = new Set(["HTMLCollection", "HTMLOptionsCollection"]);

  // WebIDL legacy platform objects with a named property getter, and whether
  // their named properties are enumerable (DOMStringMap) and writable/deletable
  // (DOMStringMap has a named setter/deleter; HTMLCollection/NamedNodeMap are
  // read-only — `coll[name] = x` / `delete coll[name]` reject in strict mode).
  const NAMED_PROP_COLLECTIONS = new Map([
    ["HTMLCollection", { enumerable: false, writable: false }],
    ["HTMLOptionsCollection", { enumerable: false, writable: false }],
    ["NamedNodeMap", { enumerable: false, writable: false }],
    ["DOMStringMap", { enumerable: true, writable: true }],
  ]);

  // [LegacyNullToEmptyString] DOMString setters: null becomes "", any other
  // value is ToString-coerced JS-side before crossing into Ruby.
  const NULL_TO_EMPTY_STRING_SETTERS = new Set(["innerHTML", "outerHTML"]);

  // Form-control value-like properties exposed as accessor descriptors on the
  // interface prototype (see protoForChain) — what React's value-tracker reads
  // and wraps to detect user input on controlled components.
  const FORM_VALUE_FIELDS = {
    HTMLInputElement: ["value", "checked"],
    HTMLTextAreaElement: ["value"],
    HTMLSelectElement: ["value"],
  };

  // Read-only WebIDL attributes that need a real getter-only descriptor on the
  // prototype: normal reads still go through the proxy get trap, but reflection
  // (Object.getOwnPropertyDescriptor walking the chain, e.g. testharness's
  // assert_readonly) must find an accessor with no [[Set]].
  const READONLY_ATTRS = {
    TreeWalker: ["root", "whatToShow", "filter"],
    NodeIterator: ["root", "whatToShow", "filter", "referenceNode", "pointerBeforeReferenceNode"],
  };

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

  // NodeFilter whatToShow bitmasks + filter return values (TreeWalker/NodeIterator).
  const NODEFILTER_CONSTANTS = {
    FILTER_ACCEPT: 1, FILTER_REJECT: 2, FILTER_SKIP: 3,
    SHOW_ALL: 0xffffffff, SHOW_ELEMENT: 0x1, SHOW_ATTRIBUTE: 0x2, SHOW_TEXT: 0x4,
    SHOW_CDATA_SECTION: 0x8, SHOW_ENTITY_REFERENCE: 0x10, SHOW_ENTITY: 0x20,
    SHOW_PROCESSING_INSTRUCTION: 0x40, SHOW_COMMENT: 0x80, SHOW_DOCUMENT: 0x100,
    SHOW_DOCUMENT_TYPE: 0x200, SHOW_DOCUMENT_FRAGMENT: 0x400, SHOW_NOTATION: 0x800
  };

  // WebSocket ready-state [Constant]s (on the interface object + prototype, so
  // `WebSocket.OPEN` and `ws.OPEN` both resolve).
  const WEBSOCKET_CONSTANTS = { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 };

  // Interface name -> its [Constant]s (placed on both the interface object and
  // its prototype; instances inherit via the proxy get `prop in target` path).
  const INTERFACE_CONSTANTS = {
    Node: NODE_CONSTANTS, Event: EVENT_CONSTANTS, NodeFilter: NODEFILTER_CONSTANTS,
    WebSocket: WEBSOCKET_CONSTANTS
  };

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
    return (typeof v === "object" || typeof v === "function") && v !== null && proxyHandles.has(v);
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
  function invokeCallback(id, args, thisArg) {
    const fn = callbacks.get(id);
    if (!fn) return undefined;
    // A null/absent thisArg keeps the historical undefined receiver; a tagged
    // value (e.g. a MutationObserver handle) sets the callback's `this`.
    const receiver = thisArg == null ? undefined : rehydrate(thisArg);
    // Catch a throwing callback and hand the thrown value back tagged, so the
    // Ruby side can decide whether to swallow (event listeners) or re-throw it
    // with identity preserved (NodeFilter, where the exception must propagate
    // out of the traversal method that ran the filter).
    try {
      return dehydrate(fn.apply(receiver, rehydrate(args || [])));
    } catch (e) {
      // Preserve the thrown value's identity through the round trip, even for a
      // plain object (`throw {name:"x"}`) which dehydrate would otherwise flatten
      // to a map — assert_throws_exactly compares by identity.
      const tagged = (e !== null && (typeof e === "object" || typeof e === "function"))
        ? { __rb_js_ref: registerJsRef(e) }
        : dehydrate(e);
      return { __rb_cb_threw__: tagged };
    }
  }

  // Enqueue a host-side microtask (by id) onto the engine's native promise-job
  // queue, so a Dommy Ruby microtask (e.g. MutationObserver delivery) runs in
  // FIFO order with JS `await`/Promise reactions rather than on a separate pass.
  function scheduleMicrotask(id) {
    Promise.resolve().then(() => { __rb_run_microtask(id); });
  }

  // Replace unpaired UTF-16 surrogates with U+FFFD. Ruby strings can't hold lone
  // surrogates, so any string crossing into Ruby loses them regardless; doing the
  // scalar-value substitution here (what the spec's USVString conversion mandates,
  // e.g. for TextEncoder) yields a single U+FFFD rather than invalid bytes.
  function scrubLoneSurrogates(s) {
    let out = "";
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        const next = s.charCodeAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) { out += s[i] + s[i + 1]; i++; }
        else out += "�";
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        out += "�";
      } else {
        out += s[i];
      }
    }
    return out;
  }

  // The spec's "flatten options": addEventListener / removeEventListener observe
  // only `capture` (plus once / passive / signal for add), each read exactly once.
  // Flattening here — before dehydrate walks the bag — means an option object's
  // unrelated getters never run (e.g. a `{ get dummy() {…} }` probe stays cold).
  function flattenListenerOptions(method, options) {
    if (options == null || typeof options !== "object") return options;
    const out = { capture: !!options.capture };
    if (method === "addEventListener") {
      out.once = !!options.once;
      out.passive = !!options.passive;
      const signal = options.signal;
      if (signal !== undefined) out.signal = signal;
    }
    return out;
  }

  function dehydrate(v, seen) {
    if (typeof v === "string") return /[\ud800-\udfff]/.test(v) ? scrubLoneSurrogates(v) : v;
    if (typeof v === "function") return { __rb_callback: registerCallback(v) };
    if (isProxy(v)) return { __rb_handle: proxyHandles.get(v) };
    // A BufferSource (ArrayBuffer or any typed-array/DataView view) crosses as
    // its raw bytes, so host code gets a uniform byte buffer (TextDecoder.decode,
    // Blob, …) rather than a key→value object from Object.keys.
    if (typeof ArrayBuffer !== "undefined") {
      if (v instanceof ArrayBuffer) return { __rb_bytes: Array.from(new Uint8Array(v)) };
      if (ArrayBuffer.isView(v)) return { __rb_bytes: Array.from(new Uint8Array(v.buffer, v.byteOffset, v.byteLength)) };
    }
    // SharedArrayBuffer is a separate type (not an ArrayBuffer subclass), but a
    // BufferSource all the same — cross it as raw bytes too.
    if (typeof SharedArrayBuffer !== "undefined" && v instanceof SharedArrayBuffer) {
      return { __rb_bytes: Array.from(new Uint8Array(v)) };
    }
    if (v !== null && typeof v === "object") {
      seen = seen || new WeakSet();
      if (seen.has(v)) return undefined; // break reference cycles
      seen.add(v);
      if (Array.isArray(v)) return v.map((e) => dehydrate(e, seen));
      // An "exotic" object — anything that is NOT a plain data object (Error,
      // DOMException, Map, a class instance, …) — crosses as an opaque JS-side
      // reference, so a value Ruby merely stores and hands back (an
      // AbortSignal's reason, a CustomEvent detail) round-trips with IDENTITY
      // rather than being flattened to a key→value map (which also loses an
      // Error's non-enumerable message/stack). Plain `{}` objects stay maps so
      // option bags keep behaving like Ruby Hashes.
      const proto = Object.getPrototypeOf(v);
      if (proto !== Object.prototype && proto !== null) {
        const ref = { __rb_js_ref: registerJsRef(v) };
        // An object implementing the EventListener interface (a `handleEvent`
        // method — e.g. Stimulus's action listeners) is a valid DOM event
        // listener. Tag it so the Ruby side wraps it as a listener whose
        // `handle_event` routes back here to call its handleEvent.
        if (typeof v.handleEvent === "function") ref.__rb_handle_event = true;
        if ("acceptNode" in v) ref.__rb_accept_node = true;
        return ref;
      }
      // A NodeFilter callback-interface object (`{ acceptNode }`) crosses as a
      // live reference so acceptNode is fetched fresh on each traverse (its
      // getter runs per call), invoked with `this` = the object, and a thrown
      // value propagates — none of which survives flattening to a map. Detected
      // with `in` so merely constructing the walker performs no Get.
      if ("acceptNode" in v) {
        return { __rb_js_ref: registerJsRef(v), __rb_accept_node: true };
      }
      const out = {};
      // Scrub lone surrogates in keys too (not just values): a property key is a
      // string the spec converts to a USVString, so `{ "\uD835x": … }` must reach
      // Ruby as "�x" — leaving it raw lets the gem mangle it (e.g. "U+d835").
      for (const k of Object.keys(v)) {
        const key = /[\ud800-\udfff]/.test(k) ? scrubLoneSurrogates(k) : k;
        out[key] = dehydrate(v[k], seen);
      }
      return out;
    }
    return v;
  }

  // Opaque JS-value registry: lets a non-plain JS object survive a round trip
  // through Ruby with identity preserved (keyed by the value so the same object
  // reuses its id). Entries are retained for the VM's lifetime.
  const jsRefs = new Map();
  const jsRefIds = new Map();
  let jsRefSeq = 0;
  function registerJsRef(v) {
    let id = jsRefIds.get(v);
    if (id === undefined) {
      id = ++jsRefSeq;
      jsRefs.set(id, v);
      jsRefIds.set(v, id);
    }
    return id;
  }

  // Called from Ruby when a host event dispatch reaches a listener that is an
  // *object* implementing EventListener (handleEvent) rather than a function.
  // Invokes handleEvent with the object itself as `this`; the tagged event is
  // rehydrated to a proxy first.
  function invokeJsRefHandleEvent(ref, event) {
    const o = jsRefs.get(ref);
    if (!o || typeof o.handleEvent !== "function") return undefined;
    return dehydrate(o.handleEvent(rehydrate(event)));
  }

  // Invoke a NodeFilter object's acceptNode for one node. acceptNode is fetched
  // fresh (running its getter, per WHATWG callback-interface invocation) and
  // called with `this` = the filter; a thrown value (from the getter or the
  // call) is tagged so the Ruby side can re-throw it out of the traversal.
  function invokeJsRefAcceptNode(ref, node) {
    const o = jsRefs.get(ref);
    if (!o) return undefined;
    try {
      const fn = o.acceptNode;
      return dehydrate(fn.call(o, rehydrate(node)));
    } catch (e) {
      const tagged = (e !== null && (typeof e === "object" || typeof e === "function"))
        ? { __rb_js_ref: registerJsRef(e) }
        : dehydrate(e);
      return { __rb_cb_threw__: tagged };
    }
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
    // A deliberate JS-native error (TypeError, RangeError, …): build the real
    // constructor so `instanceof` holds. URL construction failures arrive here
    // as TypeError (per the URL Standard), not as a DOMException.
    if (info.js_native && typeof G[info.name] === "function") {
      return new G[info.name](info.message);
    }
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
      // A host method that threw an arbitrary value (throwIfAborted's reason):
      // re-throw the rehydrated value verbatim.
      if ("__rb_throw__" in v) throw rehydrate(v.__rb_throw__);
      // A void DOM op marshals as this marker so it becomes `undefined`, not the
      // `null` a bare Ruby nil would (e.g. DOMTokenList add/remove return undefined).
      if (v.__rb_undefined) return undefined;
      // A host byte buffer (TextEncoder.encode, …) rehydrates to a Uint8Array.
      if (v.__rb_bytes) return new Uint8Array(v.__rb_bytes);
      // A host byte buffer tagged as an ArrayBuffer (Response/Blob/FileReader/
      // XHR arrayBuffer) rehydrates to a bare ArrayBuffer.
      if (v.__rb_arraybuffer) return new Uint8Array(v.__rb_arraybuffer).buffer;
      if ("__rb_handle" in v) return makeProxy(v.__rb_handle);
      // An opaque JS-value reference round-tripping back from Ruby — restore the
      // exact original object (identity-preserving).
      if ("__rb_js_ref" in v) return jsRefs.get(v.__rb_js_ref);
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

  // ===== wasm host bridge (handle-oriented JS access) =====
  //
  // A second embedding model, distinct from the Proxy-based one above: a wasm
  // guest (e.g. mruby-in-wasm under wasmtime-rb) drives JS through a small set
  // of imports — js_eval / js_global / js_get / js_set / js_call / js_new /
  // js_make_callback — that operate on opaque JS *handles*, not on Ruby objects
  // exposed as proxies. So the guest needs the inverse of makeProxy: any JS
  // value referenced by an integer ref it can get/set/call/new on.
  //
  // The marshalling is uniform: every non-primitive (object, function, DOM
  // proxy, exotic) crosses as `{ __rb_js_ref: id }` via the shared jsRefs table
  // (so a function can be the receiver of `new` or sit in a `.then(...)` arg
  // list — unlike dehydrate, which would flatten it to `{ __rb_callback }`).
  // Primitives cross as themselves. This pair (wasmTag/wasmUntag) is used only
  // by the wasm* entry points; the Proxy model's dehydrate/rehydrate are
  // untouched.
  function wasmTag(v) {
    if (v === undefined) return { __rb_undefined: true };
    if (v === null) return null;
    const t = typeof v;
    if (t === "string") return /[\ud800-\udfff]/.test(v) ? scrubLoneSurrogates(v) : v;
    if (t === "number" || t === "boolean") return v;
    if (t === "bigint") return Number(v);
    // object / function / symbol — keep identity behind a stable ref.
    return { __rb_js_ref: registerJsRef(v) };
  }

  function wasmUntag(v) {
    if (Array.isArray(v)) return v.map(wasmUntag);
    if (v !== null && typeof v === "object") {
      if (v.__rb_undefined) return undefined;
      if ("__rb_js_ref" in v) return jsRefs.get(v.__rb_js_ref);
      if (v.__rb_bytes) return new Uint8Array(v.__rb_bytes);
      if (v.__rb_arraybuffer) return new Uint8Array(v.__rb_arraybuffer).buffer;
      if ("__rb_handle" in v) return makeProxy(v.__rb_handle);
      const out = {};
      for (const k of Object.keys(v)) out[k] = wasmUntag(v[k]);
      return out;
    }
    return v;
  }

  function wasmDeref(ref) {
    const v = jsRefs.get(ref);
    if (v === undefined && !jsRefs.has(ref)) {
      throw new Error("wasm bridge: stale or unknown JS ref " + ref);
    }
    return v;
  }

  // globalThis as a (tagged) ref, so the guest's `js_global` has a handle to
  // operate on.
  function wasmGlobalRef() { return wasmTag(globalThis); }

  // Indirect eval runs in global scope: `globalThis.fetch = …` and top-level
  // var/function declarations land on the global, matching a browser's
  // host-eval escape hatch (JS.eval_javascript).
  const indirectEval = eval;
  function wasmEval(src) { return wasmTag(indirectEval(src)); }

  // Execute a connected classic <script>'s body. Called from Ruby
  // (Document#script_runner) when such a script is inserted into the document,
  // so dynamically-added scripts run as a browser would. Runs inside
  // `with (window)` so bare identifiers resolve against the window object first
  // (in a browser `window` IS the global, but here it is a distinct proxy, so
  // `window.foo = …` would otherwise be invisible to a later bare `foo`). The
  // `with` is skipped for a "use strict" body (where it is illegal). The
  // completion value is voided so a trailing expression never trips the
  // unawaited-Promise guard.
  function runScript(src) {
    const body = String(src);
    const strict = /^\s*(["'])use strict\1/.test(body);
    if (!strict && typeof globalThis.window !== "undefined" && globalThis.window !== globalThis) {
      indirectEval("with (globalThis.window) {\n" + body + "\n}\n;void 0;");
    } else {
      indirectEval(body + "\n;void 0;");
    }
  }

  function wasmGet(ref, prop) { return wasmTag(wasmDeref(ref)[prop]); }

  function wasmSet(ref, prop, value) { wasmDeref(ref)[prop] = wasmUntag(value); }

  function wasmCall(ref, method, args) {
    const recv = wasmDeref(ref);
    const fn = recv[method];
    if (typeof fn !== "function") {
      throw new TypeError("wasm bridge: " + String(method) + " is not a function");
    }
    return wasmTag(fn.apply(recv, args.map(wasmUntag)));
  }

  // Apply a function ref directly (optionally with an explicit `this` ref).
  function wasmApply(ref, thisRef, args) {
    const fn = wasmDeref(ref);
    const thisArg = thisRef == null ? undefined : wasmDeref(thisRef);
    return wasmTag(fn.apply(thisArg, args.map(wasmUntag)));
  }

  function wasmNew(ref, args) {
    const ctor = wasmDeref(ref);
    return wasmTag(Reflect.construct(ctor, args.map(wasmUntag)));
  }

  function wasmTypeof(ref) { return typeof wasmDeref(ref); }
  function wasmToString(ref) { return String(wasmDeref(ref)); }
  function wasmStrictEqual(a, b) { return wasmDeref(a) === wasmDeref(b); }
  function wasmIsNull(ref) {
    const v = jsRefs.get(ref);
    return v === null || v === undefined;
  }
  function wasmInstanceof(ref, ctorRef) {
    const ctor = wasmDeref(ctorRef);
    return typeof ctor === "function" && wasmDeref(ref) instanceof ctor;
  }

  // Create a JS function that calls back into the wasm guest by invoke-id.
  // Returned as a ref so it can be passed to Promise.then / setTimeout / etc.
  // `globalThis.__rbWasmInvoke(id, taggedArgs)` is installed by the embedder
  // (Runtime#enable_wasm_bridge!) and routes into the guest's js_invoke_proc.
  function wasmMakeCallback(invokeId) {
    const fn = function (...args) {
      const result = globalThis.__rbWasmInvoke(invokeId, args.map(wasmTag));
      return wasmUntag(result);
    };
    return wasmTag(fn);
  }

  function wasmReleaseRef(ref) {
    const v = jsRefs.get(ref);
    if (v !== undefined || jsRefs.has(ref)) {
      jsRefs.delete(ref);
      jsRefIds.delete(v);
    }
  }

  // ===== DOM interface prototypes & constructors (1a/1b/1c) =====

  // 1c: build a host object from a bare interface constructor
  // (new Event(...) / new DOMException(...)). Ruby resolves the named
  // constructor by interface name; null means "not constructable" so we throw.
  // WebIDL dictionary members for the constructors that take an init dictionary,
  // in the order the spec reads them (inherited members first, then own, each
  // group lexicographic). "boolean" members are coerced with JS ToBoolean; "any"
  // is passed through. Only interfaces with a COMPLETE member list belong here —
  // a partial list would silently drop members.
  const CONSTRUCTOR_DICTS = {
    Event: { bubbles: "boolean", cancelable: "boolean", composed: "boolean" },
    CustomEvent: { bubbles: "boolean", cancelable: "boolean", composed: "boolean", detail: "any" },
  };

  // WebIDL argument coercion for a constructor that takes `(DOMString type,
  // optional XInit dict)`: the required `type` is ToString-coerced (so a throwing
  // `toString` propagates, and a missing argument is a TypeError), and the dict
  // is rebuilt by reading ONLY its declared members, in declaration order — so
  // unrelated getters (a stray `sweet`/`dummy`) are never invoked and a member's
  // boolean coercion follows JS, not Ruby, truthiness. Other interfaces pass
  // through untouched.
  function coerceConstructorArgs(name, args) {
    if (name === "URLSearchParams") {
      // Per spec a non-string iterable init (another URLSearchParams, a Map, an
      // object with a custom @@iterator) is a *sequence* of pairs — materialize
      // it through its live iterator HERE so the iterator runs JS-side; Ruby only
      // ever sees plain pair arrays. Plain records (no @@iterator) and strings
      // fall through unchanged to the record / string paths.
      const init = args[0];
      if (init !== null && typeof init === "object" && typeof init[Symbol.iterator] === "function") {
        return [Array.from(init, (pair) => Array.from(pair))];
      }
      return args;
    }
    const members = CONSTRUCTOR_DICTS[name];
    if (!members) return args;
    if (args.length < 1) {
      throw new TypeError("Failed to construct '" + name + "': 1 argument required, but only 0 present.");
    }
    const type = String(args[0]);
    const init = args[1];
    const dict = {};
    if (init !== undefined && init !== null) {
      for (const member in members) {
        const value = init[member];
        if (value === undefined) continue;
        dict[member] = members[member] === "boolean" ? !!value : value;
      }
    }
    return [type, dict];
  }

  function constructInterface(name, args) {
    const r = rehydrate(__rb_construct(name, dehydrateArgs(coerceConstructorArgs(name, args))));
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
      // WebIDL: a value-iterator interface (indexed getter + `iterable<>`) gets
      // keys()/values()/entries()/forEach()/@@iterator whose values ARE the
      // %Array.prototype% functions — so `list.values === Array.prototype.values`.
      // They operate on the proxy via its live length + indexed getter, and each
      // returns a real Array Iterator (so `list.keys() instanceof Array` is false).
      const A = Array.prototype;
      const define = (key, fn) => Object.defineProperty(proto, key, { value: fn, configurable: true, writable: true });
      define(Symbol.iterator, A[Symbol.iterator]);
      // HTMLCollection is iterable only via @@iterator (its IDL is NOT declared
      // `iterable<>`); the keys()/values()/entries()/forEach() pair methods are
      // exclusive to interfaces that ARE (NodeList, DOMTokenList, …).
      if (!INDEXED_ONLY_ITERABLE.has(name)) {
        define("values", A.values);
        define("keys", A.keys);
        define("entries", A.entries);
        define("forEach", A.forEach);
      }
    } else if (ENTRIES_ITERABLES.has(name)) {
      // A LIVE entries iterator: re-read entries() at each step (indexed by a
      // running cursor) so a mutation mid-loop is observed — e.g. URLSearchParams
      // `for (const e of params) { params.delete(...) }` must see the new state.
      Object.defineProperty(proto, Symbol.iterator, {
        value: function () {
          let i = 0;
          const self = this;
          const it = {
            next() {
              const entries = self.entries();
              if (i >= entries.length) return { value: undefined, done: true };
              return { value: entries[i++], done: false };
            },
          };
          it[Symbol.iterator] = function () { return this; };
          return it;
        },
        configurable: true, writable: true
      });
    }
    if (name === "TextEncoder") {
      // encodeInto mutates the destination Uint8Array in place, so it must run
      // JS-side (a host round trip would only see a copy). Encodes scalar values
      // to UTF-8, stops before a code point that wouldn't fit, and returns
      // {read (source UTF-16 units), written (bytes)}.
      Object.defineProperty(proto, "encodeInto", {
        value: function (source, destination) {
          if (!(destination instanceof Uint8Array)) {
            throw new TypeError("encodeInto's destination must be a Uint8Array");
          }
          source = String(source);
          const cap = destination.length;
          let read = 0, written = 0;
          for (let i = 0; i < source.length;) {
            let cp = source.codePointAt(i);
            let units = cp > 0xffff ? 2 : 1;
            if (cp >= 0xd800 && cp <= 0xdfff) { cp = 0xfffd; units = 1; } // lone surrogate
            const need = cp <= 0x7f ? 1 : cp <= 0x7ff ? 2 : cp <= 0xffff ? 3 : 4;
            if (written + need > cap) break;
            if (need === 1) {
              destination[written++] = cp;
            } else if (need === 2) {
              destination[written++] = 0xc0 | (cp >> 6);
              destination[written++] = 0x80 | (cp & 0x3f);
            } else if (need === 3) {
              destination[written++] = 0xe0 | (cp >> 12);
              destination[written++] = 0x80 | ((cp >> 6) & 0x3f);
              destination[written++] = 0x80 | (cp & 0x3f);
            } else {
              destination[written++] = 0xf0 | (cp >> 18);
              destination[written++] = 0x80 | ((cp >> 12) & 0x3f);
              destination[written++] = 0x80 | ((cp >> 6) & 0x3f);
              destination[written++] = 0x80 | (cp & 0x3f);
            }
            read += units;
            i += units;
          }
          return { read, written };
        },
        configurable: true, writable: true,
      });
    }
    // Form-control value-like properties as real accessor descriptors on the
    // prototype, routing to the host. React's input value-tracker reads the
    // descriptor off `node.constructor.prototype` and wraps its get/set to
    // detect user edits; with no prototype accessor it bails and controlled
    // inputs never fire onChange. Normal `el.value` reads still go straight
    // through the proxy get trap (host_get); these accessors are what
    // getOwnPropertyDescriptor(prototype, …) and React's wrapper call.
    const valueFields = FORM_VALUE_FIELDS[name];
    if (valueFields) {
      for (const field of valueFields) {
        Object.defineProperty(proto, field, {
          configurable: true,
          enumerable: true,
          get() { return rehydrate(__rb_host_get(this[HKEY], field)); },
          set(v) { __rb_host_set(this[HKEY], field, dehydrate(v)); },
        });
      }
    }
    const readonlyAttrs = READONLY_ATTRS[name];
    if (readonlyAttrs) {
      for (const field of readonlyAttrs) {
        Object.defineProperty(proto, field, {
          configurable: true,
          enumerable: true,
          get() { return rehydrate(__rb_host_get(this[HKEY], field)); },
        });
      }
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
  function exposeConstructorsOnWindow(target) {
    // Defaults to the top window, but a secondary window (an iframe's
    // contentWindow) can be passed so `subWin.Element` / `subWin.DOMException`
    // resolve to the same seeded constructors — needed for cross-window
    // `instanceof` and `doc.defaultView.X` in iframe documents.
    const w = target || globalThis.window;
    if (!w) return;
    const names = [...protos.keys()];
    if (typeof globalThis.DOMException === "function") names.push("DOMException");
    // Mirror the JS built-in constructors too, so an iframe's contentWindow
    // resolves `defaultView.TypeError` / `defaultView.Array` like a real window
    // (WPT reaches for `(root.ownerDocument).defaultView.TypeError`).
    names.push(
      "Object", "Array", "Function", "String", "Boolean", "Number", "BigInt",
      "Symbol", "Date", "RegExp", "Promise", "Map", "Set", "WeakMap", "WeakSet",
      "Error", "TypeError", "RangeError", "SyntaxError", "ReferenceError",
      "Proxy", "Reflect", "JSON", "Math"
    );
    const interfaceNames = new Set(protos.keys());
    for (const name of names) {
      const ctor = globalThis[name];
      if (typeof ctor !== "function") continue;
      try {
        const current = w[name];
        // Fill in names the window doesn't resolve at all; AND replace a
        // host-backed interface object (e.g. window.Event / window.MutationObserver
        // crossing as a non-constructable Dommy proxy) with the constructable
        // seeded constructor, so `new document.defaultView.MutationObserver(cb)`
        // works — in a real window, window.X IS the constructor function X.
        if (current == null || (typeof current !== "function" && interfaceNames.has(name))) {
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
  // An array index property name: "0", "1", … (canonical, no leading zeros).
  function isArrayIndex(prop) {
    return typeof prop === "string" && /^(0|[1-9][0-9]*)$/.test(prop);
  }

  function makeHandler(handle, methods, methodCache, arrayLike, named) {
    // The live length of an array-like collection (NodeList/HTMLCollection/…),
    // so indexed own-property reflection (hasOwnProperty / Object.keys / spread)
    // tracks the current children. 0 for non-collections.
    const liveLength = () => {
      if (!arrayLike) return 0;
      const n = rehydrate(__rb_host_get(handle, "length"));
      return typeof n === "number" && n >= 0 ? n : 0;
    };
    // The live WebIDL "supported property names" (named getter keys), re-queried
    // each call so it tracks DOM mutations; [] when there is no named getter.
    const namedKeys = () => {
      if (!named) return [];
      const r = rehydrate(__rb_named_props(handle));
      return Array.isArray(r) ? r : [];
    };
    const isIndexInRange = (prop) => arrayLike && isArrayIndex(prop) && Number(prop) < liveLength();
    const isNamedKey = (prop) => named && typeof prop === "string" && namedKeys().indexOf(prop) !== -1;
    return {
      get(t, prop, receiver) {
        if (prop === HKEY) return handle;
        if (typeof prop === "symbol") return Reflect.get(t, prop, receiver);
        if (Object.hasOwn(t, prop)) return Reflect.get(t, prop, receiver);
        if (methods.has(prop)) {
          let fn = methodCache.get(prop);
          if (!fn) {
            if (prop === "addEventListener" || prop === "removeEventListener") {
              fn = (...args) => {
                if (args.length >= 3) args[2] = flattenListenerOptions(prop, args[2]);
                return rehydrate(__rb_host_call(handle, prop, dehydrateArgs(args)));
              };
            } else {
              fn = (...args) => rehydrate(__rb_host_call(handle, prop, dehydrateArgs(args)));
            }
            methodCache.set(prop, fn);
          }
          return fn;
        }
        const v = rehydrate(__rb_host_get(handle, prop));
        if (v == null && (prop in t)) return Reflect.get(t, prop, receiver);
        // A legacy platform collection returns `undefined` (not the host's null)
        // for a string property that resolves to no value. An out-of-range array
        // index is `undefined` and does NOT fall back to a named lookup (so
        // `coll[2147483648]` is undefined even if an element's id is that digit
        // string); other unsupported strings (`coll[""]`, `coll["x"]`) too.
        if (v === null && (arrayLike || named) && typeof prop === "string" && prop !== "length") {
          if (arrayLike && isArrayIndex(prop)) return undefined;
          if (!isNamedKey(prop)) return undefined;
        }
        return v;
      },
      set(t, prop, value, receiver) {
        if (typeof prop === "symbol") {
          t[prop] = value;
          if (proxyHandles.has(receiver)) pinned.set(handle, receiver);
          return true;
        }
        if (settersOf(Object.getPrototypeOf(t)).has(prop)) {
          Reflect.set(t, prop, value, receiver);
          return true;
        }
        // Legacy platform object with NO indexed setter: an array-index
        // assignment never becomes an expando — it is a no-op (sloppy) /
        // TypeError (strict), so the trap returns false.
        if (arrayLike && isArrayIndex(prop)) return false;
        // A read-only named property (HTMLCollection/NamedNodeMap) likewise
        // rejects — unless an own expando already shadows it (then update it).
        if (named && !named.writable && !Object.hasOwn(t, prop) && isNamedKey(prop)) return false;
        // WebIDL [LegacyNullToEmptyString] DOMString setters coerce JS-side
        // (null → "", else ToString — so `innerHTML = 42` / `{toString…}` work and
        // a toString that throws propagates) before the value crosses into Ruby.
        if (NULL_TO_EMPTY_STRING_SETTERS.has(prop)) value = value === null ? "" : String(value);
        const handled = __rb_host_set(handle, prop, dehydrate(value));
        // A throwing setter comes back as a tagged exception — re-throw it.
        if (handled && typeof handled === "object" && handled.__rb_exception__) {
          throw makeHostError(handled.__rb_exception__);
        }
        if (!handled) {
          t[prop] = value;
          // A genuine JS-side expando: pin the proxy so the node's JS state
          // outlives GC of this proxy (see the `pinned` declaration).
          if (proxyHandles.has(receiver)) pinned.set(handle, receiver);
        }
        return true;
      },
      // Array-like collections reflect their indices as own enumerable
      // properties so `hasOwnProperty(i)` / `Object.keys` / `{...spread}` see the
      // live children (testharness's assert_array_equals checks hasOwnProperty).
      // Named properties (HTMLCollection ids/names, dataset keys, attr names)
      // are reflected too — non-enumerable for [LegacyUnenumerableNamedProperties].
      getOwnPropertyDescriptor(t, prop) {
        if (typeof prop !== "symbol" && Object.hasOwn(t, prop)) return Reflect.getOwnPropertyDescriptor(t, prop);
        if (isIndexInRange(prop)) {
          // Indexed properties are enumerable + configurable but NOT writable
          // (these collections have no indexed property setter).
          return {
            value: rehydrate(__rb_host_get(handle, prop)),
            writable: false, enumerable: true, configurable: true,
          };
        }
        if (isNamedKey(prop)) {
          return {
            value: rehydrate(__rb_host_get(handle, prop)),
            writable: named.writable, enumerable: named.enumerable, configurable: true,
          };
        }
        return Reflect.getOwnPropertyDescriptor(t, prop);
      },
      defineProperty(t, prop, desc) {
        // Cannot redefine a live indexed or read-only named property.
        if (arrayLike && isArrayIndex(prop)) return false;
        if (named && !named.writable && !Object.hasOwn(t, prop) && isNamedKey(prop)) return false;
        return Reflect.defineProperty(t, prop, desc);
      },
      deleteProperty(t, prop) {
        if (typeof prop !== "symbol" && Object.hasOwn(t, prop)) return Reflect.deleteProperty(t, prop);
        if (isIndexInRange(prop)) return false;
        if (named && typeof prop === "string") {
          if (named.writable) {
            // Named deleter (dataset): remove the backing attribute.
            if (rehydrate(__rb_host_delete(handle, prop))) return true;
          } else if (isNamedKey(prop)) {
            return false; // read-only named property cannot be deleted
          }
        }
        return Reflect.deleteProperty(t, prop);
      },
      ownKeys(t) {
        const keys = Reflect.ownKeys(t);
        if (!arrayLike && !named) return keys;
        const n = arrayLike ? liveLength() : 0;
        const result = [];
        for (let i = 0; i < n; i++) result.push(String(i));
        for (const nm of namedKeys()) if (result.indexOf(nm) === -1) result.push(nm);
        // Then expandos / symbols that don't collide with an index or named key.
        for (const k of keys) {
          if (typeof k !== "symbol" && isArrayIndex(k) && Number(k) < n) continue;
          if (result.indexOf(k) !== -1) continue;
          result.push(k);
        }
        return result;
      },
      has(t, prop) {
        // An out-of-range index on an array-like is genuinely absent (`2 in
        // nodeList` is false past its length). A supported named key is present.
        if (arrayLike && isArrayIndex(prop)) return Number(prop) < liveLength() || Reflect.has(t, prop);
        if (isNamedKey(prop)) return true;
        // A real expando, prototype member (incl. symbols like Symbol.iterator),
        // or ABI method is present.
        if (Reflect.has(t, prop)) return true;
        if (typeof prop === "symbol") return false;
        if (methods.has(prop) || prop === "length") return true;
        // Event-handler IDL attributes (onclick, oninput, …) exist on event
        // targets as null-default properties, so `("oninput" in document)` is
        // true even when unset — React's isEventSupported feature-detect relies
        // on this to use the native input event (else it falls back to a keydown
        // polyfill and controlled-input onChange never fires).
        if (typeof prop === "string" && /^on[a-z]/.test(prop)) return true;
        // Otherwise reflect the ABI: a property whose host value is non-null is
        // present; a null/absent one reports missing. We can't distinguish
        // present-but-null from genuinely-absent across the ABI, and reporting
        // missing is what lets `(prop in proxy)` feature-detection work — e.g.
        // Stimulus's extendEvent guards on `"immediatePropagationStopped" in
        // event` before installing its override, and a blanket `true` made it
        // skip the override so stopImmediatePropagation never halted siblings.
        // Dommy distinguishes a genuinely-absent property (host returns null)
        // from one that is present-but-undefined (it returns the UNDEFINED
        // sentinel, tagged `__rb_undefined`) — e.g. AbortSignal's `reason`
        // before abort — so report the latter present (`"reason" in signal`).
        const raw = __rb_host_get(handle, prop);
        if (raw !== null && typeof raw === "object" && raw.__rb_undefined) return true;
        return rehydrate(raw) != null;
      }
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
    const p = new Proxy(target, makeHandler(handle, methods, new Map(),
      ARRAY_LIKE_COLLECTIONS.has(desc.name), NAMED_PROP_COLLECTIONS.get(desc.name) || null));
    cache.set(handle, new WeakRef(p));
    proxyHandles.set(p, handle);
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

  return {
    makeProxy, invokeCallback, invokeJsRefHandleEvent, invokeJsRefAcceptNode, runScript, scheduleMicrotask,
    tag: dehydrate, interfaceOf,
    seedInterfaces, invokeLifecycle, attachStatics, exposeConstructorsOnWindow,
    // wasm host bridge (handle-oriented access for a wasm guest)
    wasmGlobalRef, wasmEval, wasmGet, wasmSet, wasmCall, wasmApply, wasmNew,
    wasmTypeof, wasmToString, wasmStrictEqual, wasmIsNull, wasmInstanceof,
    wasmMakeCallback, wasmReleaseRef,
  };
})();
