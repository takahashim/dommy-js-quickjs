# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT WAI-ARIA role files, run through WptRunner. These drive
# `test_driver.get_computed_role` (shimmed in WptResources to Dommy's
# Element#computed_role), so they exercise the computed-role engine — explicit
# roles, the implicit HTML-AAM mappings, role fallback, synonyms, and
# presentation conflict resolution — the same surface getByRole relies on.
class Dommy::Js::TestWptWaiAriaFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    "wai-aria/role/abstract-roles.html" => { min_pass: 12, expected: [] },
    "wai-aria/role/basic.html" => { min_pass: 2, expected: [] },
    "wai-aria/role/button-roles.html" => { min_pass: 10, expected: [] },
    "wai-aria/role/contextual-roles.html" => { min_pass: 2, expected: [] },
    "wai-aria/role/fallback-roles.html" => { min_pass: 22, expected: [] },
    "wai-aria/role/form-roles.html" => { min_pass: 2, expected: [] },
    "wai-aria/role/generic-roles.html" => { min_pass: 1, expected: [] },
    "wai-aria/role/grid-roles.html" => { min_pass: 10, expected: [] },
    "wai-aria/role/invalid-roles.html" => { min_pass: 76, expected: [] },
    "wai-aria/role/list-roles.html" => { min_pass: 3, expected: [] },
    "wai-aria/role/listbox-roles.html" => { min_pass: 6, expected: [] },
    "wai-aria/role/menu-roles.html" => { min_pass: 12, expected: [] },
    "wai-aria/role/region-roles.html" => { min_pass: 2, expected: [] },
    "wai-aria/role/role_none_conflict_resolution.html" => { min_pass: 7, expected: [] },
    "wai-aria/role/roles.html" => { min_pass: 162, expected: [] },
    "wai-aria/role/synonym-roles.html" => {
      min_pass: 5,
      # This file asserts role="img"/"image" both compute to "image", whereas
      # roles.html (and every other file) expects the canonical "img" — Dommy
      # returns "img".
      expected: [
        "image role == computedrole image",
        "synonym img role == computedrole image"
      ]
    },
    "wai-aria/role/tab-roles.html" => { min_pass: 37, expected: [] },
    "wai-aria/role/table-roles.html" => { min_pass: 9, expected: [] },
    "wai-aria/role/tree-roles.html" => { min_pass: 7, expected: [] }
  )
end
