# frozen_string_literal: true

require "capybara/dommy"
require "dommy/rack"
require_relative "../quickjs"

module Dommy
  module Js
    module Quickjs
      # evaluate_async_script's callback was not called within the wait budget.
      class ScriptTimeoutError < Error; end

      # Opt-in Capybara integration. Requiring this file enables JS execution on
      # Capybara::Dommy::Driver (via install_capybara! below), so execute_script /
      # evaluate_script run against the current Dommy document through a QuickJS
      # Runtime. Without this require, capybara-dommy stays JS-free (its default).
      #
      # The realm-per-document machinery lives in SessionRuntime (shared with
      # Dommy::Rack::Session's `javascript: true`); the driver wires it to the
      # session and the Capybara polling loop, and wraps results as Capybara
      # nodes.
      module CapybaraDriver
        # The in-realm slot an async script's callback reports to. Each call
        # installs a fresh state object, so a late callback from an earlier call
        # writes into its own, now-orphaned one.
        ASYNC_SCRIPT_STATE = "__rbAsyncScriptState"

        def rack_session
          session = super
          dommy_js_attach(session)
          session
        end

        def execute_script(script, *args)
          host = dommy_js_host
          if args.empty?
            host.execute(script)
          else
            host.execute_with_args(script, capybara_script_args(args))
          end
          nil
        end

        def evaluate_script(script, *args)
          host = dommy_js_host
          value = args.empty? ? host.evaluate(script) : host.evaluate_with_args(script, capybara_script_args(args))
          decode_for_capybara(value)
        end

        # WebDriver's executeAsyncScript: the script gets a callback as its last
        # argument, and its result is whatever that callback is called with.
        # Virtual time is pumped until it is, for at most
        # Capybara.default_max_wait_time of VIRTUAL time — so a timer the script
        # waits on fires, while the budget stays deterministic.
        def evaluate_async_script(script, *args)
          host = dommy_js_host
          host.execute_with_args(<<~JS, capybara_script_args(args))
            var state = { settled: false, value: undefined };
            globalThis.#{ASYNC_SCRIPT_STATE} = state;
            var args = Array.prototype.slice.call(arguments);
            args.push(function (value) {
              if (state.settled) return;
              state.settled = true;
              state.value = value;
            });
            (function () {
            #{script}
            }).apply(this, args);
          JS
          await_async_script(host)
          decode_for_capybara(host.evaluate("globalThis.#{ASYNC_SCRIPT_STATE}.value"))
        end

        private

        def await_async_script(host)
          budget_ms = ::Capybara.default_max_wait_time * 1000
          pumps = (budget_ms / ::Dommy::Rack::SessionRuntime::PUMP_SLICE_MS).ceil
          settled = "(globalThis.#{ASYNC_SCRIPT_STATE} || {}).settled === true"
          pumps.times do
            return if host.evaluate(settled)

            host.pump
          end
          return if host.evaluate(settled)

          raise ScriptTimeoutError,
                "evaluate_async_script did not call its callback within #{budget_ms.round}ms of virtual time"
        end

        # A Capybara node argument becomes the Dommy element it wraps (so it
        # crosses to JS as a proxy), at any depth inside arrays and hashes.
        # Capybara::Session unwraps only top-level elements, so a nested
        # Capybara::Node::Element is unwrapped here too.
        def capybara_script_args(args)
          args.map { |arg| capybara_script_arg(arg) }
        end

        def capybara_script_arg(arg)
          case arg
          when ::Capybara::Node::Element then capybara_script_arg(arg.base)
          when ::Capybara::Dommy::Node then arg.native
          when Array then capybara_script_args(arg)
          when Hash then arg.transform_values { |value| capybara_script_arg(value) }
          else arg
          end
        end

        # Bind a SessionRuntime to the session (rebuilt when reset!/app_host
        # swaps the session). The driver's frame-aware `document` is the realm
        # target, and Capybara's retry loop pumps virtual time via time_pump.
        def dommy_js_attach(session)
          return if defined?(@dommy_js_session) && @dommy_js_session.equal?(session)

          @dommy_js_session = session
          @dommy_js_host = ::Dommy::Rack::SessionRuntime.new(session) { document }
          self.time_pump = -> { @dommy_js_host.pump }
        end

        # The JS host bound to the CURRENT session. Reading `rack_session` is what
        # (re)binds one, because the attach lives in that override — so this is a
        # fetch with a deliberate side effect, not a plain reader. Capybara swaps
        # the session on reset! / app_host, and the host has to follow.
        def dommy_js_host
          rack_session
          @dommy_js_host
        end

        # Map an evaluate() result to what Capybara expects:
        #   - Array            -> recurse (so element collections wrap per item)
        #   - JS undefined      -> nil
        #   - Dommy::Element    -> Capybara::Dommy::Node (covers HTML/SVG subclasses)
        #   - other host object -> nil (Document/Text/Comment/Fragment/NodeList/
        #                          Window/Blob/FormData have no Capybara
        #                          representation)
        #   - primitive/Hash    -> as-is
        def decode_for_capybara(value)
          return nil if js_undefined?(value)

          case value
          when Array then value.map { |element| decode_for_capybara(element) }
          when ::Dommy::Element then ::Capybara::Dommy::Node.new(self, value)
          else host_object?(value) ? nil : value
          end
        end

        # JS `undefined` arrives as either the engine-neutral sentinel the bridge
        # decodes to, or — on the paths that skip that decode — the gem's own.
        def js_undefined?(value)
          value.equal?(::Dommy::Bridge::UNDEFINED) || value.equal?(::Quickjs::Value::UNDEFINED)
        end

        # Whether `value` is a Dommy object the page can read properties off
        # (`__js_get__` is what the bridge calls to do that). Everything that
        # answers to it is a DOM-side object, and the ones Capybara can represent
        # were already taken by the branches above — so what is left has no
        # representation and becomes nil rather than leaking a host object into a
        # Capybara assertion.
        def host_object?(value)
          value.respond_to?(:__js_get__)
        end
      end

      # Idempotently prepend JS-execution support onto Capybara::Dommy::Driver.
      # Safe to call multiple times; only prepends once. Called on require, but
      # exposed so integration can be enabled/controlled explicitly (e.g. tests).
      def self.install_capybara!
        return if ::Capybara::Dommy::Driver.ancestors.include?(CapybaraDriver)

        ::Capybara::Dommy::Driver.prepend(CapybaraDriver)
      end
    end
  end
end

Dommy::Js::Quickjs.install_capybara!
