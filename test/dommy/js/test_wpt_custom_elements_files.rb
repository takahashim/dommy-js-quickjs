# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT custom-elements `.html` files, run through WptRunner. The
# CustomElementRegistry is now a real interface object whose operations live on
# the prototype, and customElements.define validates + reads the constructor's
# definition per WHATWG (IsConstructor, name, duplicates, the definition-running
# flag, prototype callbacks, observedAttributes / disabledFeatures sequence
# conversion, formAssociated). See host_runtime.js.
class Dommy::Js::TestWptCustomElementsFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    "custom-elements/CustomElementRegistry.html" => {
      min_pass: 43,
      expected: [
        # Cross-realm define during Get(constructor, "prototype") — the
        # definition-running flag is per-VM here, not per-registry.
        "customElements.define must not throw when defining another custom element in a different global object during Get(constructor, \"prototype\")",
        # Exact property-access ordinal (counter) for observedAttributes.
        "customElements.define must get \"observedAttributes\" property on the constructor prototype when \"attributeChangedCallback\" is present",
        # Upgrade candidates must be visited in shadow-including tree order.
        "customElements.define must upgrade elements in the shadow-including tree order"
      ]
    }
  )
end
