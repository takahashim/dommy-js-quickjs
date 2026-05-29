# frozen_string_literal: true

module Dommy
  module Js
    # Resolves a JS constructor by interface name for reverse construction
    # (`new Event(...)`, `new DOMException(...)`). The window object is the
    # source for most constructors — it exposes them via __js_get__ — while a
    # few not on the window are provided directly. Engine-agnostic.
    class ConstructorRegistry
      # The window whose __js_get__ exposes Event/CustomEvent/MouseEvent/… .
      attr_writer :source

      def initialize
        @source = nil
      end

      # An object responding to __js_new__ for `name`, or nil if `name` isn't
      # constructable (the bridge then makes the JS side throw).
      def resolve(name)
        if @source.respond_to?(:__js_get__)
          ctor = @source.__js_get__(name)
          return ctor if ctor.respond_to?(:__js_new__)
        end
        extra(name)
      end

      private

      # Constructors the window doesn't expose.
      def extra(name)
        case name
        when "DOMException"
          return unless defined?(Dommy::DOMException)

          Dommy::Bridge::Constructor.new { |args| Dommy::DOMException.new(args[0], args[1] || "Error") }
        end
      end
    end
  end
end
