# frozen_string_literal: true

require "capybara/dommy"
require "dommy/rack"
require_relative "../quickjs"

module Dommy
  module Js
    module Quickjs
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
        def rack_session
          session = super
          dommy_js_attach(session)
          session
        end

        def execute_script(script, *_args)
          dommy_js_host.execute(script)
          nil
        end

        def evaluate_script(script, *_args)
          decode_for_capybara(dommy_js_host.evaluate(script))
        end

        # No real async loop; evaluate synchronously. Sufficient for scripts
        # that resolve immediately (the common Capybara case).
        def evaluate_async_script(script, *args)
          evaluate_script(script, *args)
        end

        private

        # Bind a SessionRuntime to the session (rebuilt when reset!/app_host
        # swaps the session). The driver's frame-aware `document` is the realm
        # target, and Capybara's retry loop pumps virtual time via time_pump.
        def dommy_js_attach(session)
          return if defined?(@dommy_js_session) && @dommy_js_session.equal?(session)

          @dommy_js_session = session
          @dommy_js_host = ::Dommy::Rack::SessionRuntime.new(session) { document }
          self.time_pump = -> { @dommy_js_host.pump }
        end

        def dommy_js_host
          rack_session # ensures the host is attached for the current session
          @dommy_js_host
        end

        # Map an evaluate() result to what Capybara expects:
        #   - Array            -> recurse (so element collections wrap per item)
        #   - JS undefined      -> nil
        #   - Dommy::Element    -> Capybara::Dommy::Node (covers HTML/SVG subclasses)
        #   - other bridge obj  -> nil (Document/Text/Comment/Fragment/NodeList/
        #                          Window have no Capybara representation)
        #   - primitive/Hash    -> as-is
        def decode_for_capybara(value)
          return nil if value.equal?(::Dommy::Bridge::UNDEFINED)

          case value
          when Array
            value.map { |element| decode_for_capybara(element) }
          when ::Quickjs::Value::UNDEFINED
            nil
          when ::Dommy::Element
            ::Capybara::Dommy::Node.new(self, value)
          else
            value.respond_to?(:__js_get__) ? nil : value
          end
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
