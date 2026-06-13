# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT accessible-name (`accname/`) files. These drive
# `test_driver.get_computed_label` (shimmed to Dommy's Element#computed_label),
# exercising the accname algorithm — aria-labelledby, aria-label, native labels
# (<label>, alt, fieldset/legend, table/caption), name-from-content, and the
# title fallback. CSS-derived names (::before/::after, counters) and embedded
# control values are out of scope, so comp_name_from_content and
# comp_embedded_control are omitted.
class Dommy::Js::TestWptAccnameFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    "accname/basic.html" => { min_pass: 2, expected: [] },
    "accname/name/comp_labelledby.html" => { min_pass: 10, expected: [] },
    "accname/name/comp_text_node.html" => { min_pass: 50, expected: [] },
    "accname/name/comp_label.html" => {
      min_pass: 130,
      # visibility:hidden exclusion needs CSS layout.
      expected: ["button's hidden referenced name (visibility:hidden) with hidden aria-labelledby traversal falls back to aria-label"]
    },
    "accname/name/comp_tooltip.html" => {
      min_pass: 21,
      # <summary> name-from-contents + embedded handling.
      expected: ["summary with tooltip label and contents"]
    },
    "accname/name/comp_host_language_label.html" => {
      min_pass: 87,
      # A <label> encapsulating a <select> must exclude the control's own value.
      expected: ["html: select encapsulation"]
    }
  )
end
