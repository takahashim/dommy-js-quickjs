# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT `html/` files, run through WptRunner. Covers the History interface
# (pushState / replaceState), accessKeyLabel, and ARIA attribute reflection —
# the well-supported corners of the HTML suite.
#
# Omitted: aria-element-reflection (element-reference reflection is largely
# shadow-DOM-scoped, out of scope) and XML/foreign-document corners.
class Dommy::Js::TestWptHtmlFiles < Minitest::Test
  include Dommy::Js::WptConformance

  HISTORY = "html/browsers/history/the-history-interface"

  wpt_files(
    # --- History interface ----------------------------------------------
    "#{HISTORY}/history_pushstate.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_pushstate_err.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_pushstate_nooptionalparam.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_replacestate.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_replacestate_err.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_replacestate_nooptionalparam.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_state.html" => { min_pass: 1, expected: [] },

    # --- HTML DOM --------------------------------------------------------
    "html/dom/access-key-label.html" => { min_pass: 2, expected: [] },
    "html/dom/aria-attribute-reflection.html" => { min_pass: 41, expected: [] },
    "html/dom/aria-element-reflection-disconnected.html" => {
      min_pass: 1,
      # Element-reference reflection across disconnection (FrozenArray caching)
      # is not modeled.
      expected: ["Element references should stay valid when content is disconnected (element array)"]
    },
    "html/dom/historical.html" => {
      min_pass: 10,
      # Obsolete <applet>: Dommy still surfaces it as a normal element rather
      # than treating it as unknown/unstyled per the obsolete-features spec.
      expected: [
        "document.all cannot find applet",
        "document cannot find applet",
        "applet is not styled"
      ]
    }
  )
end
