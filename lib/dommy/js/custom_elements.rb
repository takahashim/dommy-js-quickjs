# frozen_string_literal: true

module Dommy
  module Js
    # Bridges JS-defined custom elements to Dommy's custom element pipeline.
    # `customElements.define(name, JSClass)` on the JS side calls in here, which
    # registers a Dommy::HTMLElement subclass for `name` whose lifecycle
    # reactions (connected/disconnected/adopted/attributeChanged) route back to
    # the JS instance through the bridge. The JS class's constructor itself runs
    # on the JS side via the construction-stack upgrade in host_runtime.js.
    class CustomElements
      attr_writer :window

      def initialize(bridge)
        @bridge = bridge
        @window = nil
      end

      def define(name, observed)
        return unless @window.respond_to?(:custom_elements)

        @window.custom_elements.define(name, build_class(name, observed))
        nil
      end

      # customElements.upgrade(root): delegate to Dommy's registry so a subtree
      # attached without firing reactions gets its registered elements upgraded.
      def upgrade(root)
        return unless @window.respond_to?(:custom_elements)

        @window.custom_elements.upgrade(root)
        nil
      end

      private

      # A Dommy custom element class that forwards each reaction to the JS
      # instance. `__js_custom_element_name__` marks the node so the bridge tells
      # the JS side to upgrade it on first crossing (see HostBridge interface info).
      def build_class(name, observed)
        bridge = @bridge
        Class.new(Dommy::HTMLElement) do
          define_singleton_method(:observed_attributes) { observed }
          define_method(:__js_custom_element_name__) { name }
          define_method(:connected_callback) { bridge.invoke_lifecycle(self, "connectedCallback", []) }
          define_method(:disconnected_callback) { bridge.invoke_lifecycle(self, "disconnectedCallback", []) }
          define_method(:adopted_callback) { bridge.invoke_lifecycle(self, "adoptedCallback", []) }
          define_method(:attribute_changed_callback) do |attr, old_value, new_value|
            bridge.invoke_lifecycle(self, "attributeChangedCallback", [attr, old_value, new_value])
          end
        end
      end
    end
  end
end
