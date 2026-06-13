# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT URL / URLSearchParams `.any.js` files, run through WptRunner. Dommy's
# URL implementation passes these almost entirely.
#
# url-constructor.any.js / url-origin.any.js are intentionally not registered:
# they are data-driven (a single promise_test that fetch()es the multi-hundred-
# case urltestdata.json), and the harness doesn't yet resolve that fetch — a
# separate harness concern, not a URL-parsing gap.
class Dommy::Js::TestWptUrlFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    "url/url-statics-canparse.any.js" => { min_pass: 8, expected: [] },
    "url/url-statics-parse.any.js" => { min_pass: 8, expected: [] },
    "url/url-tojson.any.js" => { min_pass: 1, expected: [] },
    "url/urlsearchparams-append.any.js" => { min_pass: 4, expected: [] },
    "url/urlsearchparams-delete.any.js" => { min_pass: 8, expected: [] },
    "url/urlsearchparams-foreach.any.js" => { min_pass: 6, expected: [] },
    "url/urlsearchparams-get.any.js" => { min_pass: 2, expected: [] },
    "url/urlsearchparams-getall.any.js" => { min_pass: 2, expected: [] },
    "url/urlsearchparams-has.any.js" => { min_pass: 4, expected: [] },
    "url/urlsearchparams-set.any.js" => { min_pass: 2, expected: [] },
    "url/urlsearchparams-size.any.js" => { min_pass: 4, expected: [] },
    "url/urlsearchparams-sort.any.js" => { min_pass: 17, expected: [] },
    "url/urlsearchparams-stringifier.any.js" => { min_pass: 14, expected: [] },
    "url/urlsearchparams-constructor.any.js" => {
      min_pass: 25,
      expected: [
        # iterating a DOMException's own enumerable props as a record, and
        # lone-surrogate key handling in the record constructor
        "URLSearchParams constructor, DOMException as argument",
        "Construct with object with NULL, non-ASCII, and surrogate keys"
      ]
    }
  )
end
