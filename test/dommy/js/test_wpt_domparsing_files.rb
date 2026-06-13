# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT DOM Parsing & Serialization (`domparsing/`) files, run through
# WptRunner. Covers innerHTML / outerHTML / insertAdjacentHTML / DOMParser —
# including the fragment parsing algorithm's "already started" flag, so a
# <script> inserted via innerHTML/insertAdjacentHTML never executes.
#
class Dommy::Js::TestWptDomParsingFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    "domparsing/XMLSerializer-serializeToString.html" => {
      min_pass: 27,
      # XLink-prefix preservation and the explicit default-namespace
      # undeclaration (xmlns="") are remaining namespace-algorithm edges.
      expected: [
        "Check if no special handling for XLink namespace unlike HTML serializer.",
        "Check if a prefix bound to an empty namespace URI (\"no namespace\") serialize"
      ]
    },
    "domparsing/DOMParser-parseFromString-html.html" => {
      min_pass: 9,
      # Synchronous <script> discovery while a CSS @import is pending — depends
      # on the parser/style interaction Dommy doesn't model.
      expected: ["script is found synchronously even when there is a css import"]
    },
    "domparsing/domparser-spurious-attributes.html" => { min_pass: 2, expected: [] },
    "domparsing/innerhtml-04.html" => { min_pass: 1, expected: [] },
    "domparsing/innerhtml-06.html" => { min_pass: 1, expected: [] },
    "domparsing/innerhtml-07.html" => { min_pass: 5, expected: [] },
    "domparsing/innerhtml-li-autoclosing.html" => { min_pass: 7, expected: [] },
    "domparsing/insert-adjacent.html" => { min_pass: 4, expected: [] },
    "domparsing/insert_adjacent_html.html" => { min_pass: 31, expected: [] },
    "domparsing/outerhtml-01.html" => { min_pass: 1, expected: [] },
    "domparsing/outerhtml-02.html" => { min_pass: 5, expected: [] },
    "domparsing/style_attribute_html.html" => { min_pass: 4, expected: [] }
  )
end
