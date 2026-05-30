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

    @win = Dommy.parse("<!DOCTYPE html><html><head></head><body><ul id='list'><li>a</li></ul></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.define_host_object("document", @win.document)
    @rt.install_window(@win)
    install_browser_globals
    @rt.execute(File.read(BUNDLE))
  end

  def teardown
    @rt&.dispose
  end

  # Turbo defers stream rendering to the next repaint; advance the deterministic
  # scheduler and drain microtasks until the work settles.
  def pump
    8.times do
      @rt.drain_microtasks
      @win.scheduler.advance_time(16)
      @rt.drain_microtasks
    end
  end

  def test_turbo_loads_and_defines_custom_elements
    assert_equal "object", @rt.evaluate("typeof globalThis.Turbo")
    assert_equal "function", @rt.evaluate('typeof customElements.get("turbo-stream")')
    assert_equal "function", @rt.evaluate('typeof customElements.get("turbo-frame")')
  end

  def test_turbo_stream_append_and_update
    @rt.execute(<<~JS)
      Turbo.renderStreamMessage('<turbo-stream action="append" target="list"><template><li>b</li></template></turbo-stream>');
    JS
    pump
    assert_equal "<li>a</li><li>b</li>", @win.document.get_element_by_id("list").inner_html

    @rt.execute(<<~JS)
      Turbo.renderStreamMessage('<turbo-stream action="update" target="list"><template><li>only</li></template></turbo-stream>');
    JS
    pump
    assert_equal "<li>only</li>", @win.document.get_element_by_id("list").inner_html
  end

  # turbo-frame lazy loading: a frame with [src] fetches its URL, Turbo parses
  # the response, extracts the matching frame and swaps its content in — the full
  # fetch -> DOMParser -> Range-based swap path.
  def test_turbo_frame_lazy_load
    @win.__js_set__("__fetchy_stub__", {
      "http://localhost/frame" => {
        "status" => 200, "contentType" => "text/html",
        "body" => '<html><body><turbo-frame id="f">LOADED CONTENT</turbo-frame></body></html>'
      }
    })
    @rt.execute(<<~JS)
      const f = document.createElement("turbo-frame");
      f.id = "f";
      f.setAttribute("src", "/frame");
      document.body.appendChild(f);
    JS
    pump
    assert_equal "LOADED CONTENT", @win.document.get_element_by_id("f").text_content.strip
  end

  private

  # Bare browser globals Turbo reaches for, aliased onto the Dommy window.
  def install_browser_globals
    @rt.execute(<<~JS)
      globalThis.self = globalThis;
      globalThis.location = window.location;
      globalThis.history = window.history;
      globalThis.navigator = window.navigator;
      globalThis.sessionStorage = window.sessionStorage;
      globalThis.localStorage = window.localStorage;
      globalThis.CSS = window.CSS;
      globalThis.fetch = (...a) => window.fetch(...a);
      globalThis.addEventListener = (...a) => window.addEventListener(...a);
      globalThis.removeEventListener = (...a) => window.removeEventListener(...a);
      globalThis.dispatchEvent = (e) => window.dispatchEvent(e);
    JS
  end
end
