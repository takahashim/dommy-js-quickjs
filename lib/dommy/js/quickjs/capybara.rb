# frozen_string_literal: true

require "capybara/dommy"
require "dommy/rack/network_bridge"
require_relative "../quickjs"

module Dommy
  module Js
    module Quickjs
      # Opt-in Capybara integration. Requiring this file enables JS execution on
      # Capybara::Dommy::Driver (via install_capybara! below), so execute_script /
      # evaluate_script run against the current Dommy document through a QuickJS
      # Runtime. Without this require, capybara-dommy stays JS-free (its default).
      module CapybaraDriver
        TIME_PUMP_SLICE_MS = 50

        def rack_session
          session = super
          dommy_js_subscribe_to_session(session)
          session
        end

        def execute_script(script, *_args)
          dommy_js_runtime.execute(script)
          nil
        end

        def evaluate_script(script, *_args)
          decode_for_capybara(dommy_js_runtime.evaluate(script))
        end

        # No real async loop; evaluate synchronously. Sufficient for scripts
        # that resolve immediately (the common Capybara case).
        def evaluate_async_script(script, *args)
          evaluate_script(script, *args)
        end

        private

        def dommy_js_subscribe_to_session(session)
          return if defined?(@dommy_js_subscribed_session) && @dommy_js_subscribed_session.equal?(session)

          session.on_document_loaded do |window|
            dommy_js_on_page_load(session, window)
          end
          @dommy_js_subscribed_session = session
        end

        # A top-level navigation invalidates every realm: drop the old top
        # window's VM AND any frame VMs built under it (their documents are
        # gone), then eagerly build the new top realm so its window/network
        # bridge are live before any script runs. dommy-rack invokes
        # on_document_loaded after every HTML navigation, so VM lifetime follows
        # browser page lifetimes instead of waiting for the first execute call.
        def dommy_js_on_page_load(session, window)
          @dommy_js_session = session
          dommy_js_dispose_all
          dommy_js_runtime_for(window.document)
          self.time_pump = -> { dommy_js_pump }
        end

        # The Runtime for the driver's CURRENT document — the top page, or the
        # innermost switched-to frame. Each window is its own realm (its own
        # globals, listeners, timers), so it gets its own VM, kept in a map
        # keyed by document identity rather than rebuilt on every switch (which
        # would destroy the other realm's JS state). execute/evaluate target
        # this. Built lazily so a direct call before the first navigation, or a
        # frame entered via switch_to_frame (which does NOT fire a page load),
        # still gets a runtime pointed at the right document.
        def dommy_js_runtime
          dommy_js_runtime_for(document)
        end

        # Build-or-fetch the realm VM for one document. The network bridge needs
        # the session; it is absent only on the direct-call-before-navigation
        # fallback path (then JS fetch falls through to the stub map, as before).
        def dommy_js_runtime_for(doc)
          (@dommy_js_runtimes ||= {}.compare_by_identity)[doc] ||= begin
            rt = Runtime.new
            rt.define_host_object("document", doc)
            if (window = doc&.default_view)
              rt.install_window(window)
              rt.install_browser_globals
              ::Dommy::Rack::NetworkBridge.install(@dommy_js_session, window) if @dommy_js_session
            end
            rt
          end
        end

        # Advance virtual time and settle microtasks across EVERY live realm, so
        # a timer in any window (top or frame) makes progress while Capybara
        # polls. Iterates a snapshot: a fired timer may navigate and replace the
        # map mid-pump.
        def dommy_js_pump
          return unless @dommy_js_runtimes

          @dommy_js_runtimes.to_a.each do |doc, runtime|
            doc&.default_view&.scheduler&.advance_time(TIME_PUMP_SLICE_MS)
            runtime.drain_microtasks
          end
        end

        def dommy_js_dispose_all
          @dommy_js_runtimes&.each_value(&:dispose)
          @dommy_js_runtimes = {}.compare_by_identity
        end

        # Map an evaluate() result to what Capybara expects:
        #   - Array            -> recurse (so element collections wrap per item)
        #   - JS undefined      -> nil
        #   - Dommy::Element    -> Capybara::Dommy::Node (covers HTML/SVG subclasses)
        #   - other bridge obj  -> nil (Document/Text/Comment/Fragment/NodeList/
        #                          Window have no Capybara representation; a browser
        #                          likewise returns non-serializable values as null)
        #   - primitive/Hash    -> as-is
        def decode_for_capybara(value)
          # Runtime#evaluate decodes a JS `undefined` to the Dommy bridge's
          # UNDEFINED sentinel (an opaque object, not :undefined); a browser's
          # executeScript returns null for it, so map it to nil.
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
