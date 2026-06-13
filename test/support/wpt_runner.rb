# frozen_string_literal: true

require "json"
require "dommy/browser"
require_relative "wpt_harness"
require_relative "wpt_resources"

module Dommy
  module Js
    # Runs a vendored WPT test file the way a browser does: the file is loaded
    # as the document and its own `<script>` tags boot through ScriptBoot, with
    # testharness.js / testharnessreport.js / sibling helpers served by
    # WptResources. No regex extraction or manual script concatenation — the
    # parsed DOM and the real resource/script pipeline drive everything.
    #
    #   results = WptRunner.run("css/cssom/CSSStyleSheet.html")  # => [Result, …]
    #
    # Handles the two WPT file shapes:
    #   * `.html`                — markup whose inline `<script>` blocks hold the
    #                              test
    #   * `.any.js`/`.window.js`  — a bare test script (with `// META: script=`
    #     include directives), wrapped in a generated harness page
    class WptRunner
      WPT_ROOT = WptResources::WPT_ROOT
      Result = WptHarness::Result

      META_SCRIPT = %r{^\s*//\s*META:\s*script=(\S+)}.freeze
      # testharness's harness timeout is 10s; pump past it so a stuck async test
      # is marked TIMEOUT and the rest are still harvested.
      PUMP_ROUNDS = 250
      PUMP_STEP_MS = 100

      class << self
        def available? = WptResources.available?

        # Runnable test files under the vendored tree, relative to WPT_ROOT.
        def manifest
          ::Dir.glob("**/*.{any,window}.js", base: WPT_ROOT)
            .concat(::Dir.glob("**/*.{html,htm}", base: WPT_ROOT))
            .reject { |p| p.start_with?("common/") || p.include?("/resources/") || p.end_with?("-ref.html") }
            .sort
        end

        def run(rel_path)
          path = absolute(rel_path)
          html = page_for(path, rel_path)
          url = "http://localhost/#{rel_path.delete_prefix('/')}"

          browser = ::Dommy::Browser.new(
            html, url: url, resources: WptResources.build,
            execute_scripts: true, strict: false, settle: false
          )
          harvest(browser)
        ensure
          browser&.dispose
        end

        private

        def absolute(rel_path)
          return rel_path if ::File.absolute_path?(rel_path) && ::File.exist?(rel_path)

          ::File.join(WPT_ROOT, rel_path)
        end

        # The document to load: an `.html` test is its own page; a `.js` test is
        # wrapped in a generated harness page that pulls in testharness, the
        # report shim, its META includes, and the test body — all as `<script>`
        # tags ScriptBoot runs in order.
        def page_for(path, rel_path)
          source = ::File.read(path)
          return source if rel_path.end_with?(".html", ".htm")

          includes = source.scan(META_SCRIPT).flatten
            .map { |spec| %(<script src="#{resolve_include(spec, rel_path)}"></script>) }
          <<~HTML
            <!DOCTYPE html><html><head>
            <script src="/resources/testharness.js"></script>
            <script src="/resources/testharnessreport.js"></script>
            #{includes.join("\n")}
            <script>#{source}</script>
            </head><body></body></html>
          HTML
        end

        # A META `script=` spec is "/"-rooted at the WPT tree or relative to the
        # test file; either way return a URL path the resource layer resolves
        # (file_system serves the vendored tree by path).
        def resolve_include(spec, rel_path)
          spec = spec.sub(/\?.*\z/, "")
          return spec if spec.start_with?("/")

          dir = ::File.dirname("/#{rel_path.delete_prefix('/')}")
          ::File.expand_path(spec, dir)
        end

        # Fire the load event (testharness defers completion until it), then
        # drain microtasks/timers until the completion callback stashes results
        # or the pump budget is spent.
        def harvest(browser)
          browser.execute('window.dispatchEvent(new Event("load"));')
          browser.settle
          if browser.evaluate("globalThis.__wptResults === null")
            PUMP_ROUNDS.times do
              browser.advance_time(PUMP_STEP_MS)
              break unless browser.evaluate("globalThis.__wptResults === null")
            end
          end

          # Harvest as a JSON string, not by dehydrating the JS array directly:
          # the bridge sometimes hands back opaque host objects rather than
          # Hashes, and WPT names/messages can carry control characters that
          # JSON escapes safely.
          json = browser.evaluate("JSON.stringify(globalThis.__wptResults)")
          return [] unless json.is_a?(::String) && !json.empty?

          ::JSON.parse(json).map { |r| Result.new(r["name"], r["status"], r["message"]) }
        end
      end
    end
  end
end
