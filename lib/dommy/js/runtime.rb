# frozen_string_literal: true

module Dommy
  module Js
    # The Runtime port: the contract a JS engine must satisfy to drive a Dommy
    # DOM. `Dommy::Browser` and `Dommy::Js::ScriptBoot` depend on this interface,
    # never on a concrete engine — so a backend (QuickJS today, others later) is
    # a pluggable implementation registered through `Dommy::Js.register_runtime`.
    #
    # This module is documentation + a conformance check, not a base class:
    # engines satisfy it by duck typing (no inheritance), and `conforms?` /
    # `assert_conformance!` verify the surface so a partial backend fails fast
    # with a clear message instead of an obscure NoMethodError mid-boot.
    #
    # The contract, as the host layer uses it:
    #
    #   Lifecycle / wiring
    #     install_window(window)        seed the realm's window globals + DOM
    #     install_browser_globals       CSS / fetch / addEventListener / ...
    #     define_host_object(name, obj) expose a Ruby object under a JS global
    #     on_unhandled_rejection { |e } observe uncaught promise rejections
    #     on_log { |entry| }            observe console.* output
    #     dispose                       tear down the realm
    #
    #   Script boot (driven by ScriptBoot)
    #     set_document_ready_state(s)   replay loading/interactive/complete
    #     module_loader = callable      install the ESM resolver Proc
    #     load_script(js)               run a classic inline script
    #     load_script_cached(js, cache_key:)  run external script, cache bytecode
    #     load_module_url(url)          run an ES module by URL
    #
    #   Driving / settling
    #     execute(js)                   run for side effects
    #     evaluate(js)                  run and decode the result
    #     settle                        drain microtasks + due-now timers + rAF
    #     drain_microtasks              drain the microtask queue only
    #
    # Optional (a backend may omit these; callers must guard with respond_to?):
    #     install_wasm_memory_shim      opt-in WPT SharedArrayBuffer scaffolding
    module Runtime
      # The methods every conforming runtime must respond to.
      REQUIRED_METHODS = %i[
        install_window install_browser_globals define_host_object
        on_unhandled_rejection on_log dispose
        set_document_ready_state module_loader= load_script load_script_cached load_module_url
        execute evaluate settle drain_microtasks
      ].freeze

      # Methods a backend may implement but is not required to.
      OPTIONAL_METHODS = %i[install_wasm_memory_shim].freeze

      module_function

      # The required methods `obj` does not respond to (empty when conforming).
      def missing_methods(obj)
        REQUIRED_METHODS.reject { |m| obj.respond_to?(m) }
      end

      def conforms?(obj) = missing_methods(obj).empty?

      # Raise unless `obj` satisfies the contract, naming what is missing.
      def assert_conformance!(obj)
        missing = missing_methods(obj)
        return obj if missing.empty?

        raise ArgumentError,
          "#{obj.class} is not a conforming Dommy::Js::Runtime " \
          "(missing: #{missing.join(", ")})"
      end
    end

    # Registry of JS runtime backends, keyed by name. A backend gem registers a
    # factory on load (e.g. dommy-js-quickjs registers :quickjs); the host layer
    # builds runtimes through `build_runtime` instead of naming a concrete class.
    @runtime_factories = {}
    @default_runtime = nil

    class << self
      # The name of the backend `build_runtime` uses when none is given. Set by
      # the first backend to register (and overridable by the host).
      attr_accessor :default_runtime

      # Register a runtime factory under `name`. The factory receives the keyword
      # options passed to `build_runtime` and must return an object satisfying
      # the Runtime contract. The first registration becomes the default.
      def register_runtime(name, &factory)
        raise ArgumentError, "a factory block is required" unless factory

        @runtime_factories[name.to_sym] = factory
        @default_runtime ||= name.to_sym
        name.to_sym
      end

      def runtime_registered?(name) = @runtime_factories.key?(name.to_sym)

      def registered_runtimes = @runtime_factories.keys

      # Build a runtime from the named backend (or the default), passing `opts`
      # to its factory. Verifies the result conforms before handing it back.
      def build_runtime(name = nil, **opts)
        name = (name || @default_runtime)&.to_sym
        factory = @runtime_factories[name]
        unless factory
          raise ArgumentError,
            "unknown JS runtime backend #{name.inspect} " \
            "(registered: #{registered_runtimes.inspect})"
        end

        Runtime.assert_conformance!(factory.call(**opts))
      end
    end
  end
end
