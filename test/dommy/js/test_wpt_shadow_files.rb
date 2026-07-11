# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT shadow-dom `.html` files, run through WptRunner. These exercise the
# WebIDL interface surface (attachShadow / shadowRoot placed on the correct
# prototype, not Node/CharacterData/Document) — now that DOM members are seeded
# onto interface prototypes (see host_runtime.js INTERFACE_MEMBERS) rather than
# answered only via the instance proxy traps.
class Dommy::Js::TestWptShadowFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    "shadow-dom/Element-interface-attachShadow.html" => { min_pass: 6, expected: [] },
    "shadow-dom/Element-interface-shadowRoot-attribute.html" => { min_pass: 3, expected: [] },
    "shadow-dom/Slottable-mixin.html" => { min_pass: 4, expected: [] },
    "shadow-dom/ShadowRoot-interface.html" => {
      min_pass: 10,
      # A disconnected <style>'s `sheet` is null per spec, but Dommy builds a sheet
      # unconditionally (making it conditional on connectivity breaks the CSS
      # cascade). So the two "not connected → sheet null" style-sheet cases fail.
      expected: [
        "ShadowRoot.styleSheets must return a StyleSheetList sequence containing the shadow root style sheets when shadow root is open.",
        "ShadowRoot.styleSheets must return a StyleSheetList sequence containing the shadow root style sheets when shadow root is closed."
      ]
    }
  )
end
