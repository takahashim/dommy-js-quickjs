# frozen_string_literal: true

require_relative "wpt_harness"

module Dommy
  module Js
    # Turns a vendored WPT test file into something WptHarness can run, then
    # runs it. Handles the two file shapes WPT ships:
    #
    #   * `.any.js` / `.window.js` — a pure test script, optionally preceded by
    #     `// META: script=PATH` include directives and `fetch("resources/…")`
    #     of sibling data files.
    #   * `.html` — markup whose inline `<script>` blocks hold the test, with
    #     `<script src>` pulling in testharness + helpers.
    #
    # For `.js` files the document is a bare page; for `.html` the file itself is
    # the document (so fixture markup is queryable). META `script=` includes and
    # non-testharness `<script src>` helpers are resolved against the vendored
    # WPT tree and prepended. `fetch(...)` of a sibling resource that exists on
    # disk is served from a stub keyed by the literal URL the test passes.
    #
    #   prepared = WptRunner.prepare("url/url-constructor.any.js")
    #   results  = WptRunner.run("url/url-constructor.any.js")   # => [Result, …]
    class WptRunner
      WPT_ROOT = ::File.expand_path("../fixtures/wpt", __dir__)
      DEFAULT_HTML = "<!DOCTYPE html><html><head></head><body></body></html>"

      META_SCRIPT = /^\s*\/\/\s*META:\s*script=(\S+)/.freeze
      SCRIPT_TAG  = /<script\b([^>]*)>(.*?)<\/script>/mi.freeze
      IFRAME_TAG  = /<iframe\b([^>]*)>/i.freeze
      # A dynamic `frame.src = "…"` assignment to an `.html`/`.htm`/`.xht` resource.
      IFRAME_SRC_ASSIGN = /\.src\s*=\s*["']([^"']+\.(?:html|htm|xht)[^"']*)["']/i.freeze
      # WPT uses both quoted and unquoted attributes (`src=../common.js`).
      SRC_ATTR    = /\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.freeze
      FETCH_CALL  = /\bfetch\(\s*["']([^"']+)["']/.freeze

      Prepared = Struct.new(:html, :script, :fetch_stub, :iframe_docs, :missing_includes, keyword_init: true)

      class << self
        def available? = WptHarness.available? && ::File.directory?(WPT_ROOT)

        # All runnable test files under the vendored tree, as paths relative to
        # WPT_ROOT (so `url/foo.any.js`). `resources/` data files and `common/`
        # helpers are excluded — they're includes, not tests.
        def manifest
          ::Dir.glob("**/*.{any,window}.js", base: WPT_ROOT)
            .concat(::Dir.glob("**/*.{html,htm}", base: WPT_ROOT))
            .reject { |p| p.start_with?("common/") || p.include?("/resources/") }
            .sort
        end

        def run(rel_or_abs)
          prepared = prepare(rel_or_abs)
          wpt = WptHarness.new(prepared.html, fetch_stub: prepared.fetch_stub, iframe_docs: prepared.iframe_docs)
          wpt.run(prepared.script)
        ensure
          wpt&.dispose
        end

        # Resolve includes/fetch deps without running — useful for inspection.
        def prepare(rel_or_abs)
          path = absolute(rel_or_abs)
          dir = ::File.dirname(path)
          source = ::File.read(path)

          if path.end_with?(".html", ".htm")
            prepare_html(source, dir)
          else
            prepare_js(source, dir)
          end
        end

        private

        def absolute(rel_or_abs)
          return rel_or_abs if ::File.absolute_path?(rel_or_abs) && ::File.exist?(rel_or_abs)

          ::File.join(WPT_ROOT, rel_or_abs)
        end

        def prepare_js(source, dir)
          missing = []
          includes = source.scan(META_SCRIPT).flatten.filter_map do |spec|
            inc = resolve_include(spec, dir)
            next read_or_record(inc, spec, missing)
          end

          Prepared.new(
            html: DEFAULT_HTML,
            script: (includes + [source]).join("\n;\n"),
            fetch_stub: fetch_stub_for(source, dir),
            iframe_docs: nil,
            missing_includes: missing
          )
        end

        def prepare_html(source, dir)
          missing = []
          helpers = []
          inline = []

          source.scan(SCRIPT_TAG) do |attrs, body|
            m = attrs.match(SRC_ATTR)
            src = m && (m[1] || m[2] || m[3])
            if src
              # testharness itself is loaded by WptHarness; skip its <script src>.
              next if src.include?("testharness")

              inc = resolve_include(src, dir)
              code = read_or_record(inc, src, missing)
              helpers << code if code
            elsif !body.strip.empty?
              inline << body
            end
          end

          Prepared.new(
            html: source,
            script: (helpers + inline).join("\n;\n"),
            fetch_stub: fetch_stub_for(source, dir),
            iframe_docs: iframe_docs_for(source, dir),
            missing_includes: missing
          )
        end

        # Map each iframe content `src` to the markup of its resource (when it
        # exists on disk), so the harness can populate `iframe.contentDocument` —
        # both static `<iframe src=…>` and dynamic `frame.src = "…"` assignments
        # (Selectors-API tests create an iframe and run their suite on load).
        # Keyed by the fragment-stripped src so `…content.html#target` resolves.
        def iframe_docs_for(source, dir)
          docs = {}
          add_iframe_doc = lambda do |src|
            next unless src

            clean = src.sub(/#.*\z/, "")
            file = resolve_include(clean, dir)
            docs[clean] = ::File.read(file) if ::File.exist?(file)
          end

          source.scan(IFRAME_TAG) { |attrs,| add_iframe_doc.call(attrs.match(SRC_ATTR)&.values_at(1, 2, 3)&.compact&.first) }
          source.scan(IFRAME_SRC_ASSIGN) { |src,| add_iframe_doc.call(src) }
          docs.empty? ? nil : docs
        end

        # `/foo` is rooted at the WPT tree; anything else is relative to the
        # test file's directory.
        def resolve_include(spec, dir)
          spec = spec.sub(/\?.*\z/, "") # drop query (variant markers)
          if spec.start_with?("/")
            ::File.join(WPT_ROOT, spec.sub(%r{\A/}, ""))
          else
            ::File.expand_path(spec, dir)
          end
        end

        def read_or_record(path, spec, missing)
          return ::File.read(path) if ::File.exist?(path)

          missing << spec
          nil
        end

        # Serve any `fetch("…")` whose target exists as a sibling resource on
        # disk, keyed by the exact string the test passes to fetch().
        def fetch_stub_for(source, dir)
          stub = {}
          source.scan(FETCH_CALL).flatten.uniq.each do |url|
            file = ::File.expand_path(url, dir)
            next unless ::File.exist?(file)

            content_type = url.end_with?(".json") ? "application/json" : "text/plain"
            stub[url] = {"status" => 200, "body" => ::File.read(file), "contentType" => content_type}
          end
          stub.empty? ? nil : stub
        end
      end
    end
  end
end
