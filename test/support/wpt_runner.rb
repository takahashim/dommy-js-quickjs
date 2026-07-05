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
          resources = WptResources.build

          # Boot with execute_scripts: false so the window `load` event has NOT
          # fired yet — script boot replays "complete -> load", and tests that
          # read `iframe.contentDocument` inside a `load` handler need static
          # `<iframe src>` frames navigated BEFORE that. We wire them, then drive
          # script boot ourselves (which fires load with the frames in place).
          browser = ::Dommy::Browser.new(
            html, url: url, resources: resources,
            execute_scripts: false, strict: false, settle: false,
            wasm_memory_shim: true
          )
          boot_scripts(browser, url, resources)
          harvest(browser, url, resources)
        ensure
          browser&.dispose
        end

        # Replicate Dommy::Browser's script-boot step, but only after the initial
        # (static) iframes have been navigated — so the window load event that
        # boot dispatches sees their contentDocument populated.
        def boot_scripts(browser, base_url, resources)
          wire_iframes(browser, base_url, resources)
          doc = browser.window.document
          doc.external_script_runner = lambda do |element, src|
            ::Dommy::Js::ScriptBoot.run_external_script(browser.runtime, doc, element, src, resources: resources)
          end
          ::Dommy::Js::ScriptBoot.run_document_scripts(browser.runtime, doc, resources: resources)
          browser.settle
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
        # wptserve `.sub.` template substitutions, mapped onto the single-host
        # harness: the document's own host and default ports stay same-origin,
        # while the "second" ports and alternate hosts become distinct (cross-
        # origin) URLs the path-based resource layer still serves. Enough for the
        # CORS `.sub` tests that hard-code `http://{{host}}:{{ports[http][1]}}/…`.
        WPT_SUBS = {
          "{{host}}" => "localhost",
          "{{ports[http][0]}}" => "80", "{{ports[http][1]}}" => "8001",
          "{{ports[https][0]}}" => "443", "{{ports[https][1]}}" => "8444",
          "{{ports[ws][0]}}" => "80", "{{ports[wss][0]}}" => "443",
          "{{domains[]}}" => "localhost", "{{domains[www2]}}" => "www2.localhost",
          "{{hosts[alt][]}}" => "not-localhost.test",
          "{{hosts[alt][www2]}}" => "www2.not-localhost.test",
        }.freeze

        def page_for(path, rel_path)
          source = ::File.read(path)
          source = WPT_SUBS.reduce(source) { |s, (k, v)| s.gsub(k, v) } if rel_path.include?(".sub.")
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

        # Script boot has already fired the load event; drain microtasks/timers
        # until the completion callback stashes results or the pump budget is
        # spent. `base_url` resolves `<iframe src>` against the vendored tree.
        def harvest(browser, base_url, resources)
          wire_iframes(browser, base_url, resources)
          if browser.evaluate("globalThis.__wptResults === null")
            PUMP_ROUNDS.times do
              browser.advance_time(PUMP_STEP_MS)
              # Tests that build their subtests inside an `<iframe>` create the
              # frame dynamically (frame.src = "...content.html"), so re-wire
              # each round until its onload fires and the body runs.
              wire_iframes(browser, base_url, resources)
              break unless browser.evaluate("globalThis.__wptResults === null")
            end
          end

          # Harvest as a JSON string, not by dehydrating the JS array directly:
          # the bridge sometimes hands back opaque host objects rather than
          # Hashes, and WPT names/messages can carry control characters that
          # JSON escapes safely.
          json = browser.evaluate("JSON.stringify(globalThis.__wptResults)")
          return [] unless json.is_a?(::String) && !json.empty?

          parsed = ::JSON.parse(json)
          # A never-completing test (e.g. one gated on an iframe that never
          # loaded) leaves `__wptResults` as JS null → parses to Ruby nil. Don't
          # let that crash the whole file's harvest; report nothing instead.
          return [] unless parsed.is_a?(::Array)

          parsed.map { |r| Result.new(r["name"], r["status"], r["message"]) }
        end

        # Populate any `<iframe src=...>` whose src resolves against the vendored
        # tree with a parsed content document, then fire the frame's `load` event
        # — the browser doesn't navigate iframes itself, but WPT tests routinely
        # run their body inside a framed document (Selectors-API suites, the
        # createElementNS XML/XHTML-document cases via /common/dummy.{xml,xhtml}).
        # Idempotent: an already-wired frame is skipped, so it is safe to call
        # every pump round for dynamically created frames.
        def wire_iframes(browser, base_url, resources)
          browser.window.document.query_selector_all("iframe").each do |iframe|
            next if iframe.content_document

            src = iframe.get_attribute("src").to_s
            src = "" if src == "about:blank"
            srcdoc = iframe.get_attribute("srcdoc")
            sub =
              if !src.empty?
                resolved = resolve_url(base_url, src)
                response = resources.get(resolved.sub(/#.*\z/, ""))
                next unless response&.success? && response.body

                parse_framed_document(response.body, resolved)
              else
                # A srcless (blank/about:blank) or `srcdoc` iframe gets its own
                # empty/srcdoc document, so `contentWindow` resolves and its
                # cross-realm globals (contentWindow.AbortSignal / DOMException /
                # Comment) are available — used by dom/abort + constructor tests.
                ::Dommy.parse(srcdoc.to_s.empty? ? "<!DOCTYPE html><html><head></head><body></body></html>" : srcdoc.to_s)
              end
            next unless sub

            iframe.__internal_set_content_document__(sub.document)
            browser.runtime.expose_constructors_on(sub)
            iframe.dispatch_event(::Dommy::Event.new("load"))
          end
        rescue StandardError
          # Wiring is best-effort; a malformed frame must not abort the harvest.
          nil
        end

        # Parse framed markup according to the resource extension: XML/XHTML get
        # the XML parser (case-preserving, real namespaces) so createElement /
        # namespaceURI match the spec; everything else parses as HTML.
        def parse_framed_document(body, resolved)
          path = resolved.sub(/[#?].*\z/, "")
          win =
            if path.end_with?(".xml", ".xhtml")
              w = ::Dommy::Window.new(nil, backend_doc: ::Dommy::Backend.parse_xml(body))
              w.document.content_type = path.end_with?(".xhtml") ? "application/xhtml+xml" : "text/xml"
              w
            else
              ::Dommy.parse(body)
            end
          # Carry the URL (incl. fragment) onto the framed window so `:target` /
          # location.hash resolve in the framed document.
          win.location.__internal_set_url__(resolved) if resolved.include?("#")
          win
        rescue StandardError
          nil
        end

        # Resolve a possibly-relative iframe src against the test's URL.
        def resolve_url(base_url, src)
          ::URI.join(base_url, src).to_s
        rescue ::URI::Error
          src
        end
      end
    end
  end
end
