# frozen_string_literal: true

require "test_helper"

# A heavy real-site SPA (note.com's Apollo/React bundle + the whole DOM mirrored
# as host proxies) can exhaust QuickJS's memory. The gem flags the VM "poisoned"
# after an out-of-memory and any further eval may segfault — so the host must
# STOP driving it, not crash the whole browser. This pins that contract: once a
# VM is poisoned, the backend's drive points no-op instead of raising, so the
# event loop (the dommynx tick that advances time) keeps the page alive showing
# whatever rendered before its JS died.
class Dommy::Js::TestOomResilience < Minitest::Test
  Backend = Dommy::Js::Quickjs::Backend
  Config = Dommy::Js::Quickjs::Config

  def test_a_poisoned_vm_stops_being_driven_instead_of_crashing
    backend = Backend.new(memory_limit: 8 * 1024 * 1024) # tiny ceiling to force OOM fast

    # Allocate without bound until the VM runs out of memory: the gem raises and
    # marks the VM poisoned. Whether an OOM poisons the VM (vs. unwinding as a
    # recoverable JS exception) depends on the allocator's state, so this file
    # runs in its own process (see the Rakefile) to stay deterministic.
    assert_raises(::Quickjs::RuntimeError) do
      backend.eval("var a = []; for (;;) { a.push(new Array(100000).fill(7)); }")
    end
    assert backend.poisoned?, "the VM is flagged poisoned after out-of-memory"

    # Every drive point must now no-op rather than raise "VM is poisoned" — that
    # raise (out of the microtask drain) is exactly what crashed dommynx.
    assert_nil backend.drain_microtasks
    assert_nil backend.eval("1 + 1")
    assert_nil backend.call_js("Math.max", 1, 2)
  end

  # The guard has to cover EVERY way of running something, or the answer depends
  # on which one the host happened to reach for: an inline script quietly did
  # nothing after an out-of-memory while an external (bytecode) one and
  # #evaluate raised "VM is poisoned" from a different place each time.
  def test_every_way_of_running_something_no_ops_on_a_poisoned_vm
    backend = Backend.new(memory_limit: 8 * 1024 * 1024)
    compiled = Backend.compile("globalThis.ran = true;", filename: "probe.js")

    assert_raises(::Quickjs::RuntimeError) do
      backend.eval("var a = []; for (;;) { a.push(new Array(100000).fill(7)); }")
    end
    assert backend.poisoned?

    assert_nil backend.eval_awaited("1 + 1"), "the awaited eval behind #evaluate"
    assert_nil backend.run_compiled(compiled), "the bytecode path behind an external script"
    assert_nil backend.run_bundle("probe.js", "globalThis.ran = true;"), "an engine bundle"
    assert_nil backend.import_module_url("http://example.test/m.js"), "an ES module"
    assert_nil backend.run_gc
  end

  def test_the_memory_ceiling_honors_the_env_override
    original = ENV["DOMMY_JS_MEMORY_LIMIT_MB"]

    ENV.delete("DOMMY_JS_MEMORY_LIMIT_MB")
    assert_equal Config::DEFAULT_MEMORY_LIMIT, Config.memory_limit

    ENV["DOMMY_JS_MEMORY_LIMIT_MB"] = "16"
    assert_equal 16 * 1024 * 1024, Config.memory_limit

    ENV["DOMMY_JS_MEMORY_LIMIT_MB"] = "0" # junk/zero keeps the default, as the timeout does
    assert_equal Config::DEFAULT_MEMORY_LIMIT, Config.memory_limit
  ensure
    ENV["DOMMY_JS_MEMORY_LIMIT_MB"] = original
  end

  # The per-eval timeout is the ceiling on how long QuickJS holds the thread in C
  # (blocking a deferred Ctrl-C). An interactive host lowers it via the env var;
  # the library default is unchanged when unset.
  def test_eval_timeout_honors_the_env_override
    original = ENV["DOMMY_JS_TIMEOUT_MSEC"]

    ENV.delete("DOMMY_JS_TIMEOUT_MSEC")
    assert_equal Config::DEFAULT_TIMEOUT_MSEC, Config.timeout_msec

    ENV["DOMMY_JS_TIMEOUT_MSEC"] = "15000"
    assert_equal 15_000, Config.timeout_msec

    ENV["DOMMY_JS_TIMEOUT_MSEC"] = "0" # ignore a junk/zero value, keep the default
    assert_equal Config::DEFAULT_TIMEOUT_MSEC, Config.timeout_msec
  ensure
    ENV["DOMMY_JS_TIMEOUT_MSEC"] = original
  end
end
