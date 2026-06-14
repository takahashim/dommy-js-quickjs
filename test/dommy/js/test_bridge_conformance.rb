# frozen_string_literal: true

require "test_helper"
require "dommy/js/bridge_conformance"

# Runs the shared, engine-agnostic BridgeConformance suite (shipped from core)
# against the REAL QuickJS runtime — so the host_runtime.js half and the Ruby
# Marshaller half are proven to agree across the actual JS boundary, not just
# Ruby-side. `round_trip` sends a value Ruby -> JS -> Ruby through a host object:
# reading `probe.value` hands the value to JS (Marshaller#wrap, then
# host_runtime.js rehydrate), and `probe.capture(x)` brings it back
# (host_runtime.js dehydrate, then Marshaller#unwrap).
class Dommy::Js::TestBridgeConformance < Minitest::Test
  include Dommy::Js::BridgeConformance

  # A host object exposed to JS as `probe`: `probe.value` is the Ruby value on
  # its way out, `probe.capture(x)` records a JS value on its way back in.
  class Probe
    attr_accessor :value, :captured

    def __js_get__(key)
      key == "value" ? @value : nil
    end

    def __js_method_names__
      %w[capture]
    end

    def __js_call__(method, args)
      @captured = args[0] if method == "capture"
      Dommy::Bridge::UNDEFINED
    end
  end

  def setup
    @win = Dommy.parse("<!doctype html><html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @probe = Probe.new
    @rt.define_host_object("probe", @probe)
  end

  def teardown
    @rt&.dispose
  end

  # Ruby -> JS -> Ruby across the real QuickJS bridge.
  def round_trip(value)
    @probe.value = value
    @probe.captured = nil
    @rt.execute("probe.capture(probe.value);")
    @probe.captured
  end

  # Use a real DOM node for the identity round-trip (a node is the canonical
  # bridge-able object, and crosses with a seeded interface like real code).
  def conformance_bridgeable_object
    @win.document.create_element("div")
  end
end
