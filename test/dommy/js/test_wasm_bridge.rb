# frozen_string_literal: true

require "test_helper"

# Exercises the handle-oriented wasm host bridge (WasmBridge + the `wasm*`
# functions on __rbHost). This is the surface a wasm guest (mruby-in-wasm under
# wasmtime-rb, i.e. Lilac's test runner) drives through its js_* imports.
class Dommy::Js::TestWasmBridge < Minitest::Test
  JSValue = Dommy::Js::Quickjs::WasmBridge::JSValue

  def setup
    @win = Dommy.parse("<div id='root'><h1 class='title'>Hi</h1></div>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
    @rt.define_host_object("document", @win.document)
    @b = @rt.wasm_bridge
    @global = @b.global_ref
  end

  def teardown
    @rt&.dispose
  end

  def test_global_ref_is_a_handle
    assert_instance_of JSValue, @global
  end

  def test_eval_returns_primitives
    assert_equal 3, @b.eval_js("1 + 2")
    assert_equal "ok", @b.eval_js("'ok'")
    assert_equal true, @b.eval_js("true")
    assert_nil @b.eval_js("null")
  end

  def test_get_set_roundtrip_on_global
    @b.set(@global, "answer", 42)
    assert_equal 42, @b.get(@global, "answer")
    assert_equal 42, @b.eval_js("globalThis.answer")
  end

  def test_object_returns_as_handle_and_get_reaches_in
    obj = @b.eval_js("({ a: 1, nested: { b: 2 } })")
    # A plain object still crosses as a ref (uniform handle model), so the guest
    # navigates it with further get calls rather than receiving a flattened map.
    assert_instance_of JSValue, obj
    assert_equal 1, @b.get(obj, "a")
    nested = @b.get(obj, "nested")
    assert_equal 2, @b.get(nested, "b")
  end

  def test_call_method_on_object
    arr = @b.eval_js("[1, 2, 3]")
    assert_equal 4, @b.call(arr, "push", [4]) # Array#push returns the new length
    assert_equal 4, @b.get(arr, "length")
    assert_equal "1,2,3,4", @b.to_string(arr)
  end

  def test_construct
    ctor = @b.get(@global, "Array")
    arr = @b.construct(ctor, [])
    @b.call(arr, "push", ["x"])
    assert_equal "x", @b.get(arr, "0")
  end

  def test_dom_access_through_refs
    doc = @b.get(@global, "document")
    h1 = @b.call(doc, "querySelector", ["h1"])
    assert_equal "Hi", @b.get(h1, "textContent")
    @b.set(h1, "textContent", "Bye")
    assert_equal "Bye", @win.document.query_selector("h1").text_content
  end

  def test_typeof_and_instanceof
    fn = @b.eval_js("(function () {})")
    assert_equal "function", @b.typeof(fn)
    arr = @b.eval_js("[1]")
    array_ctor = @b.get(@global, "Array")
    assert_equal true, @b.instance_of?(arr, array_ctor)
  end

  # The crux for Lilac: a guest callback invoked from JS routes back through
  # __rbWasmInvoke, and async (Promise + setTimeout on Dommy's scheduler)
  # settles under run_until_idle.
  def test_make_callback_invoked_from_promise_then
    fired = []
    @b.on_invoke do |invoke_id, args|
      fired << [invoke_id, @b.unpack(args[0])]
      @b.pack(nil)
    end
    on_ok = @b.make_callback(7)
    promise = @b.eval_js("Promise.resolve('payload')")
    @b.call(promise, "then", [on_ok])
    assert_empty fired
    @rt.run_until_idle
    assert_equal [[7, "payload"]], fired
  end

  def test_make_callback_through_settimeout
    ticks = []
    @b.on_invoke do |invoke_id, _args|
      ticks << invoke_id
      @b.pack(nil)
    end
    cb = @b.make_callback(11)
    set_timeout = @b.get(@global, "setTimeout")
    @b.apply(set_timeout, nil, [cb, 10])
    assert_empty ticks
    @rt.run_until_idle
    assert_equal [11], ticks
  end

  # The flush_async! shape: new Promise(cb => setTimeout(cb, 0)) then resolved.
  def test_promise_constructor_with_guest_executor
    resolved = []
    # The executor receives (resolve, reject) as JS function refs; the guest
    # schedules resolve on a timer, mirroring Lilac.flush_async!.
    @b.on_invoke do |invoke_id, args|
      if invoke_id == 1 # executor
        resolve = @b.unpack(args[0])
        set_timeout = @b.get(@global, "setTimeout")
        @b.apply(set_timeout, nil, [resolve, 0])
      else # the .then continuation
        resolved << invoke_id
      end
      @b.pack(nil)
    end
    executor = @b.make_callback(1)
    promise_ctor = @b.get(@global, "Promise")
    promise = @b.construct(promise_ctor, [executor])
    cont = @b.make_callback(2)
    @b.call(promise, "then", [cont])
    @rt.run_until_idle
    assert_equal [2], resolved
  end
end
