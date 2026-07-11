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
    "shadow-dom/Element-interface-shadowRoot-attribute.html" => { min_pass: 3, expected: [] }
  )
end
