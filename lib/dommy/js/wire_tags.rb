# frozen_string_literal: true

module Dommy
  module Js
    # The wire protocol shared by every Ruby<->JS marshaller in this gem: the
    # tagged-Hash shapes that cross the boundary (a handle, a callback, an opaque
    # JS ref, a byte buffer, a tagged exception, …). Both Ruby marshallers —
    # HostBridge#wrap/#unwrap (the Proxy bridge) and WasmBridge#pack/#unpack (the
    # wasm guest bridge) — build and match these keys, so keeping them as one set
    # of constants prevents the two sides from drifting apart.
    #
    # The JS half (host_runtime.js: dehydrate/rehydrate/wasmTag/wasmDeref) mirrors
    # the SAME string literals. When changing a tag here, update host_runtime.js
    # in lockstep — these constants are the canonical names; the JS literals are
    # the mirror.
    module WireTags
      # A bridged Ruby object, referenced by its HandleTable id (becomes an ES
      # Proxy on the JS side).
      HANDLE = "__rb_handle"
      # A live JS function that crossed into Ruby, referenced by callback id.
      CALLBACK = "__rb_callback"
      # An opaque JS value referenced by its id in the JS-side `jsRefs` table
      # (shared by the Proxy and wasm bridges). See Dommy::Bridge::JSValue.
      JS_REF = "__rb_js_ref"
      # A human-readable label captured alongside a JS ref (for #to_s/#inspect).
      JS_LABEL = "__rb_js_label"
      # Marks a JS ref that implements the EventListener interface (handleEvent).
      HANDLE_EVENT = "__rb_handle_event"
      # Marks a JS ref that implements the NodeFilter interface (acceptNode).
      ACCEPT_NODE = "__rb_accept_node"
      # The JS `undefined` value (distinct from null / Ruby nil).
      UNDEFINED = "__rb_undefined"
      # A byte buffer crossing as a JS Uint8Array.
      BYTES = "__rb_bytes"
      # A byte buffer crossing as a bare JS ArrayBuffer.
      ARRAY_BUFFER = "__rb_arraybuffer"
      # A host-raised DOMException/TypeError/RangeError, re-thrown JS-side.
      EXCEPTION = "__rb_exception__"
      # An arbitrary host-thrown value, re-thrown JS-side verbatim.
      THROW = "__rb_throw__"
      # A callback whose JS invocation threw (the thrown value is carried here).
      CALLBACK_THREW = "__rb_cb_threw__"
    end
  end
end
