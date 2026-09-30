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
      # Two cases contradict others in the file; Dommy writes what Chrome,
      # WebKit and Firefox all write (an agreeing xmlns="" is kept, an
      # attribute keeps its own unbound prefix), and fails these two as every
      # browser does.
      expected: [
        "Check if redundant xmlns=\"...\" is dropped.",
        "Check if the prefix of an attribute is NOT preserved in a case where neither its prefix nor its namespace URI is not already used."
      ]
    },
    "domparsing/DOMParser-parseFromString-html.html" => {
      min_pass: 9,
      # Synchronous <script> discovery while a CSS @import is pending — depends
      # on the parser/style interaction Dommy doesn't model.
      expected: ["script is found synchronously even when there is a css import"]
    },
    "domparsing/createContextualFragment.html" => {
      min_pass: 34,
      # A <script> parsed via createContextualFragment must run when the fragment
      # is later inserted into the document — Dommy doesn't execute scripts on
      # dynamic DOM insertion (only parser/document boot scripts run).
      expected: ["<script>s should be run when appended to the document (but not before)"]
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
