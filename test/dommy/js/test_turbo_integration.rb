# frozen_string_literal: true

require "test_helper"

# Drives the *real* @hotwired/turbo UMD bundle on Dommy + QuickJS — the
# end-to-end proof that the bridge can host a real framework. Skips unless the
# bundle is vendored at test/fixtures/turbo.umd.js (fetch it with:
#   curl -sL https://unpkg.com/@hotwired/turbo@8/dist/turbo.es2017-umd.js \
#     -o test/fixtures/turbo.umd.js
# ).
class Dommy::Js::TestTurboIntegration < Minitest::Test
  BUNDLE = File.expand_path("../../fixtures/turbo.umd.js", __dir__)

  def setup
    skip "Turbo bundle not vendored (#{BUNDLE})" unless File.exist?(BUNDLE)

    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head></head><body><ul id='list'><li>a</li></ul></body></html>"
    )
    @h.load_script(BUNDLE)
  end

  def teardown
    @h&.dispose
  end

  def test_turbo_loads_and_defines_custom_elements
    assert_equal "object", @h.evaluate("typeof globalThis.Turbo")
    assert_equal "function", @h.evaluate('typeof customElements.get("turbo-stream")')
    assert_equal "function", @h.evaluate('typeof customElements.get("turbo-frame")')
    assert_empty @h.errors, @h.error_report
  end

  def test_turbo_stream_append_and_update
    @h.execute(<<~JS)
      Turbo.renderStreamMessage('<turbo-stream action="append" target="list"><template><li>b</li></template></turbo-stream>');
    JS
    @h.pump
    assert_equal "<li>a</li><li>b</li>", list_html

    @h.execute(<<~JS)
      Turbo.renderStreamMessage('<turbo-stream action="update" target="list"><template><li>only</li></template></turbo-stream>');
    JS
    @h.pump
    assert_equal "<li>only</li>", list_html
    assert_empty @h.errors, @h.error_report
  end

  # turbo-frame lazy loading: a frame with [src] fetches its URL, Turbo parses
  # the response, extracts the matching frame and swaps its content in — the full
  # fetch -> DOMParser -> Range-based swap path.
  def test_turbo_frame_lazy_load
    @h.stub_fetch(
      "http://localhost/frame" => {
        "status" => 200, "contentType" => "text/html",
        "body" => '<html><body><turbo-frame id="f">LOADED CONTENT</turbo-frame></body></html>'
      }
    )
    @h.execute(<<~JS)
      const f = document.createElement("turbo-frame");
      f.id = "f";
      f.setAttribute("src", "/frame");
      document.body.appendChild(f);
    JS
    @h.pump
    assert_equal "LOADED CONTENT", @h.window.document.get_element_by_id("f").text_content.strip
    assert_empty @h.errors, @h.error_report
  end

  private

  def list_html
    @h.window.document.get_element_by_id("list").inner_html
  end
end
