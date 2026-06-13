# frozen_string_literal: true

require_relative "wpt_runner"

module Dommy
  module Js
    # Shared scaffolding for the per-area "real WPT files" conformance suites
    # (test_wpt_<area>_files.rb). Each suite registers a map of vendored test
    # file -> { min_pass:, expected: } via `wpt_files`, which defines one test
    # method per file. A file passes when it yields >= min_pass subtests AND
    # every failing subtest is "expected": a documented gap (layout-dependent,
    # an unimplemented interface, ...). A new/regressed failure — or a pass
    # count below the baseline — fails the build; a previously-failing subtest
    # that starts passing is tolerated (improvements don't need a baseline bump).
    #
    #   expected: an Array of exact subtest names, or a Proc(name) -> bool for a
    #   category of failures (e.g. ->(n) { n.include?("width") } for layout).
    module WptConformance
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def wpt_files(expected_map)
          expected_map.each do |file, spec|
            method_name = "test_#{file.gsub(/[^a-z0-9]+/i, '_')}"
            define_method(method_name) do
              skip "WPT not vendored" unless Dommy::Js::WptRunner.available?

              assert_wpt_file(file, min_pass: spec[:min_pass], expected: spec[:expected])
            end
          end
        end
      end

      def assert_wpt_file(file, min_pass:, expected:)
        results = Dommy::Js::WptRunner.run(file)
        refute_empty results, "#{file}: harness produced no subtests"

        passed = results.count(&:pass?)
        assert_operator passed, :>=, min_pass,
          "#{file}: #{passed} pass, below baseline #{min_pass} (a regression)"

        unexpected = results.reject(&:pass?).map(&:name).reject { |name| expected_failure?(expected, name) }
        assert_empty unexpected, "#{file}: unexpected (new) failures:\n  #{unexpected.join("\n  ")}"
      end

      def expected_failure?(expected, name)
        case expected
        when ::Proc then expected.call(name)
        else Array(expected).include?(name)
        end
      end
    end
  end
end
