# frozen_string_literal: true

require "capybara/dommy"
require_relative "../quickjs"

module Dommy
  module Js
    module Quickjs
      # Opt-in Capybara integration. Requiring this file enables JS execution on
      # Capybara::Dommy::Driver (via install_capybara! below), so execute_script /
      # evaluate_script run against the current Dommy document through a QuickJS
      # Runtime. Without this require, capybara-dommy stays JS-free (its default).
      module CapybaraDriver
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

        # One Runtime per document. Rebuilt when navigation swaps the document
        # so JS always sees the current page (and the old VM is released).
        def dommy_js_runtime
          doc = document
          unless defined?(@dommy_js_doc) && @dommy_js_doc.equal?(doc)
            @dommy_js_runtime&.dispose
            @dommy_js_runtime = Runtime.new
            @dommy_js_runtime.define_host_object("document", doc)
            view = doc.default_view
            @dommy_js_runtime.install_window(view) if view
            @dommy_js_doc = doc
          end
          @dommy_js_runtime
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
