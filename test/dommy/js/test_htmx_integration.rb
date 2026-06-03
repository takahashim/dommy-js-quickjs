# frozen_string_literal: true

require "test_helper"

# Drives the *real* htmx bundle on Dommy + QuickJS. htmx is server-driven and
# attribute-based (hx-get/hx-post → XHR → swap response HTML), so it exercises
# the XHR stub + HTML swapping path (a Turbo-adjacent style popular in Rails).
# Skips unless the bundle is vendored:
#   curl -sL https://unpkg.com/htmx.org@1/dist/htmx.min.js -o test/fixtures/htmx.umd.js
#
# Note: htmx requests over XMLHttpRequest, and opens it with the URL exactly as
# authored (hx-get="/hello" → "/hello"), so the fetch stub is keyed by that
# literal path — Dommy's XHR reads the same stub map as fetch.
class Dommy::Js::TestHtmxIntegration < Minitest::Test
  BUNDLE = File.expand_path("../../fixtures/htmx.umd.js", __dir__)

  def setup
    skip "htmx bundle not vendored (#{BUNDLE})" unless File.exist?(BUNDLE)
  end

  def teardown
    @h&.dispose
  end

  def boot(html, fetch_stub:)
    @h = Dommy::Js::BrowserHarness.new(html, fetch_stub: fetch_stub)
    @h.load_script(BUNDLE)
    @h.pump(rounds: 20)
    @h
  end

  def doc = @h.window.document

  def test_htmx_loads
    boot("<!DOCTYPE html><html><head></head><body></body></html>", fetch_stub: {})
    assert_equal "object", @h.evaluate("typeof htmx")
    assert_empty @h.errors, @h.error_report
  end

  # hx-get on click fetches the URL and swaps the response into the target.
  def test_hx_get_swaps_into_target
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<button id='b' hx-get='/hello' hx-target='#result' hx-swap='innerHTML'>Load</button>" \
      "<div id='result'>initial</div></body></html>",
      fetch_stub: { "/hello" => { "status" => 200, "contentType" => "text/html", "body" => "<p>HELLO</p>" } }
    )
    assert_equal "initial", doc.get_element_by_id("result").inner_html

    @h.execute("document.getElementById('b').click();")
    @h.pump(rounds: 40)
    assert_equal "<p>HELLO</p>", doc.get_element_by_id("result").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # hx-post with hx-swap="outerHTML" replaces the triggering element itself.
  def test_hx_post_outer_html_swap
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div id='box' hx-post='/submit' hx-trigger='click' hx-swap='outerHTML'>click me</div></body></html>",
      fetch_stub: { "/submit" => { "status" => 200, "contentType" => "text/html", "body" => "<div id='box'>POSTED</div>" } }
    )
    assert_equal "click me", doc.get_element_by_id("box").text_content

    @h.execute("document.getElementById('box').click();")
    @h.pump(rounds: 40)
    assert_equal "POSTED", doc.get_element_by_id("box").text_content
    assert_empty @h.errors, @h.error_report
  end

  # hx-trigger names a non-default event; firing it drives the request.
  def test_hx_trigger_custom_event
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<input id='f' hx-get='/search' hx-trigger='search' hx-target='#out'>" \
      "<div id='out'></div></body></html>",
      fetch_stub: { "/search" => { "status" => 200, "contentType" => "text/html", "body" => "RESULTS" } }
    )
    @h.execute("document.getElementById('f').dispatchEvent(new Event('search', { bubbles: true }));")
    @h.pump(rounds: 40)
    assert_equal "RESULTS", doc.get_element_by_id("out").text_content
    assert_empty @h.errors, @h.error_report
  end
end
