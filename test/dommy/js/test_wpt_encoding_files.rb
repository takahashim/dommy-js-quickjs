# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT Encoding (TextEncoder / TextDecoder) `.any.js` files. Dommy's codecs
# pass these almost entirely; the few gaps are detached-ArrayBuffer edge cases
# (no real transfer/detach) recorded as expected failures.
class Dommy::Js::TestWptEncodingFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    "encoding/api-basics.any.js" => { min_pass: 6, expected: [] },
    "encoding/api-surrogates-utf8.any.js" => { min_pass: 6, expected: [] },
    "encoding/textdecoder-fatal.any.js" => { min_pass: 36, expected: [] },
    "encoding/textdecoder-ignorebom.any.js" => { min_pass: 4, expected: [] },
    "encoding/textdecoder-copy.any.js" => { min_pass: 2, expected: [] },
    "encoding/textencoder-utf16-surrogates.any.js" => { min_pass: 7, expected: [] },
    # textdecoder-eof is intentionally omitted: both of its test() blocks mix in
    # Big5 cases, and the Big5 codec is out of scope (no legacy multi-byte
    # tables). UTF-8 end-of-queue / streaming flush behavior itself is correct
    # and is exercised by textdecoder-fatal / api-* above.
    "encoding/encodeInto.any.js" => {
      min_pass: 110,
      expected: ["encodeInto() and a detached output buffer"] # no ArrayBuffer detach
    },
    "encoding/textdecoder-arguments.any.js" => {
      min_pass: 3,
      expected: ["TextDecoder decode() with array buffer detached during arg conversion"]
    }
  )
end
