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

    load_page("<!DOCTYPE html><html><head></head><body><ul id='list'><li id='x'>a</li></ul></body></html>")
  end

  # (Re)build the harness around `html` and load the Turbo bundle. Tests that
  # need a different starting document (turbo-frame, morph) call this to replace
  # the default page set up above. `fetch_stub:` seeds the stub BEFORE Turbo
  # boots — needed for preloading, which fetches on session start.
  def load_page(html, fetch_stub: nil)
    @h&.dispose
    @h = Dommy::Js::BrowserHarness.new(html, fetch_stub: fetch_stub)
    @h.load_script(BUNDLE)
    @h
  end

  # Render a single turbo-stream message (action attrs + template inner HTML)
  # and pump the scheduler so the swap lands.
  def stream(action_attrs, inner)
    @h.execute(
      "Turbo.renderStreamMessage('<turbo-stream #{action_attrs}>" \
      "<template>#{inner}</template></turbo-stream>');"
    )
    @h.pump
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
    assert_equal '<li id="x">a</li><li>b</li>', list_html

    @h.execute(<<~JS)
      Turbo.renderStreamMessage('<turbo-stream action="update" target="list"><template><li>only</li></template></turbo-stream>');
    JS
    @h.pump
    assert_equal "<li>only</li>", list_html
    assert_empty @h.errors, @h.error_report
  end

  # The remaining turbo-stream actions (append/update are covered above):
  # prepend / before / after / replace / remove. Each drives the real Turbo
  # StreamActions through customElements + DOMParser + the Range-based swap.
  def test_turbo_stream_prepend_before_after
    stream('action="prepend" target="list"', "<li>z</li>")
    assert_equal '<li>z</li><li id="x">a</li>', list_html

    stream('action="before" target="x"', "<li>b4</li>")
    assert_equal '<li>z</li><li>b4</li><li id="x">a</li>', list_html

    stream('action="after" target="x"', "<li>af</li>")
    assert_equal '<li>z</li><li>b4</li><li id="x">a</li><li>af</li>', list_html
    assert_empty @h.errors, @h.error_report
  end

  def test_turbo_stream_replace_and_remove
    stream('action="replace" target="x"', '<li id="x">R</li>')
    assert_equal '<li id="x">R</li>', list_html

    @h.execute('Turbo.renderStreamMessage(\'<turbo-stream action="remove" target="x"></turbo-stream>\');')
    @h.pump
    assert_equal "", list_html
    assert_empty @h.errors, @h.error_report
  end

  # Turbo Drive: a programmatic visit fetches the destination, parses the
  # response document, and swaps <body> + updates <title> — the full
  # navigation/render pipeline (not just streams/frames).
  def test_turbo_drive_visit
    @h.stub_fetch(
      "http://localhost/page2" => {
        "status" => 200, "contentType" => "text/html",
        "body" => "<html><head><title>Page 2</title></head>" \
                  "<body><ul id='list'><li>NAV</li></ul></body></html>"
      }
    )
    @h.execute('Turbo.visit("/page2");')
    @h.pump(rounds: 40)

    assert_equal "Page 2", @h.evaluate("document.title")
    assert_equal "<li>NAV</li>", list_html
    assert_empty @h.errors, @h.error_report
  end

  # Turbo form submission: a POST form whose response is a turbo-stream is
  # intercepted, fetched, and the stream applied — the form -> fetch ->
  # stream-render path.
  def test_turbo_form_submission_renders_stream
    @h.stub_fetch(
      "http://localhost/submit" => {
        "status" => 200, "contentType" => "text/vnd.turbo-stream.html",
        "body" => '<turbo-stream action="append" target="list">' \
                  "<template><li>FORM</li></template></turbo-stream>"
      }
    )
    @h.execute(<<~JS)
      const form = document.createElement("form");
      form.setAttribute("action", "/submit");
      form.setAttribute("method", "post");
      const btn = document.createElement("button");
      btn.setAttribute("type", "submit");
      form.appendChild(btn);
      document.body.appendChild(form);
      form.requestSubmit();
    JS
    @h.pump(rounds: 40)

    assert_equal '<li id="x">a</li><li>FORM</li>', list_html
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

  # A form INSIDE a turbo-frame: Turbo intercepts the submit, fetches the
  # action, and swaps in only the matching <turbo-frame id> from the response
  # (the rest of the page is ignored) — frame-scoped navigation.
  def test_turbo_frame_form_submission
    load_page(<<~HTML)
      <!DOCTYPE html><html><head></head><body>
      <turbo-frame id="f">
        <p id="content">ORIGINAL</p>
        <form id="frm" action="/frame-submit" method="post"><button type="submit">go</button></form>
      </turbo-frame>
      </body></html>
    HTML
    @h.stub_fetch(
      "http://localhost/frame-submit" => {
        "status" => 200, "contentType" => "text/html",
        "body" => '<html><body><turbo-frame id="f"><p id="content">UPDATED</p></turbo-frame></body></html>'
      }
    )
    @h.execute('document.getElementById("frm").requestSubmit();')
    @h.pump(rounds: 40)

    frame = @h.window.document.get_element_by_id("f")
    assert_equal "UPDATED", frame.query_selector("#content").text_content
    assert_empty @h.errors, @h.error_report
  end

  # Turbo 8 morphing: a `<meta name="turbo-refresh-method" content="morph">`
  # page, refreshed via a `<turbo-stream action="refresh">`, is reconciled with
  # idiomorph — existing nodes are MUTATED IN PLACE (identity + JS state
  # preserved) rather than replaced. We prove the morph (not a full swap) by
  # checking a held node reference and a JS expando survive while text changes.
  def test_turbo_morph_refresh_preserves_identity
    load_page(<<~HTML)
      <!DOCTYPE html><html><head><meta name="turbo-refresh-method" content="morph"></head>
      <body><h1 id="keep">Title</h1><p id="content">ORIGINAL</p></body></html>
    HTML
    @h.stub_fetch(
      "http://localhost/" => {
        "status" => 200, "contentType" => "text/html",
        "body" => '<html><head><meta name="turbo-refresh-method" content="morph"></head>' \
                  '<body><h1 id="keep">Title</h1><p id="content">MORPHED</p></body></html>'
      }
    )
    @h.execute(<<~JS)
      globalThis.__keep = document.getElementById("keep");
      globalThis.__keep.__marker = "STILL_HERE";
    JS
    @h.execute('Turbo.renderStreamMessage(\'<turbo-stream action="refresh"></turbo-stream>\');')
    @h.pump(rounds: 60)

    assert_equal "morph", @h.evaluate("Turbo.session.view.snapshot.refreshMethod")
    assert_equal "MORPHED", @h.evaluate('document.getElementById("content").textContent')
    # The <h1> node was morphed in place, not replaced:
    assert_equal true, @h.evaluate('globalThis.__keep === document.getElementById("keep")')
    assert_equal true, @h.evaluate("globalThis.__keep.isConnected")
    assert_equal "STILL_HERE", @h.evaluate('document.getElementById("keep").__marker')
    assert_empty @h.errors, @h.error_report
  end

  # Turbo Drive intercepts a real <a href> click and navigates (fetch + swap).
  # Note this exercises Turbo's `el.closest("a[href], a[xlink\\:href]")` link
  # detection, which runs on EVERY document click.
  def test_turbo_drive_link_click
    load_page("<!DOCTYPE html><html><head></head><body><a id='lnk' href='/page2'>go</a><p id='c'>HOME</p></body></html>")
    @h.stub_fetch("http://localhost/page2" => {
      "status" => 200, "contentType" => "text/html",
      "body" => "<html><head><title>P2</title></head><body><p id='c'>PAGE2</p></body></html>"
    })
    @h.execute('document.getElementById("lnk").click();')
    @h.pump(rounds: 40)

    assert_equal "PAGE2", @h.evaluate('document.getElementById("c").textContent')
    assert_equal "P2", @h.evaluate("document.title")
    assert_empty @h.errors, @h.error_report
  end

  # A link INSIDE a turbo-frame navigates only the frame; the rest of the page
  # is untouched.
  def test_turbo_frame_link_navigation
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<turbo-frame id='f'><a id='lnk' href='/inner'>go</a></turbo-frame>" \
              "<p id='out'>OUTSIDE</p></body></html>")
    @h.stub_fetch("http://localhost/inner" => {
      "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><turbo-frame id='f'>FRAME-NAV</turbo-frame></body></html>"
    })
    @h.execute('document.getElementById("lnk").click();')
    @h.pump(rounds: 40)

    assert_equal "FRAME-NAV", @h.window.document.get_element_by_id("f").text_content.strip
    assert_equal "OUTSIDE", @h.window.document.get_element_by_id("out").text_content
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo-frame: a link OUTSIDE a frame drives that frame by id.
  def test_data_turbo_frame_targeting
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<a id='lnk' href='/inner' data-turbo-frame='f'>go</a>" \
              "<turbo-frame id='f'>ORIG</turbo-frame></body></html>")
    @h.stub_fetch("http://localhost/inner" => {
      "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><turbo-frame id='f'>TARGETED</turbo-frame></body></html>"
    })
    @h.execute('document.getElementById("lnk").click();')
    @h.pump(rounds: 40)

    assert_equal "TARGETED", @h.window.document.get_element_by_id("f").text_content.strip
    assert_empty @h.errors, @h.error_report
  end

  # turbo-stream targets="<css selector>" applies the action to every match.
  def test_turbo_stream_targets_selector
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<div class='box'>1</div><div class='box'>2</div></body></html>")
    @h.execute('Turbo.renderStreamMessage(\'<turbo-stream action="update" targets=".box">' \
               "<template>X</template></turbo-stream>');")
    @h.pump

    texts = @h.window.document.query_selector_all(".box").map(&:text_content)
    assert_equal %w[X X], texts
    assert_empty @h.errors, @h.error_report
  end

  # turbo-stream action="replace" method="morph": a TARGETED morph (idiomorph on
  # one element subtree), preserving node identity within the target.
  def test_turbo_stream_morph_method
    load_page("<!DOCTYPE html><html><head></head><body><div id='t'><p id='c'>OLD</p></div></body></html>")
    @h.execute('globalThis.__p = document.getElementById("c"); globalThis.__p.__m = "M";')
    @h.execute('Turbo.renderStreamMessage(\'<turbo-stream action="replace" method="morph" target="t">' \
               '<template><div id="t"><p id="c">NEW</p></div></template></turbo-stream>\');')
    @h.pump

    assert_equal "NEW", @h.evaluate('document.getElementById("c").textContent')
    assert_equal true, @h.evaluate('globalThis.__p === document.getElementById("c")')
    assert_equal "M", @h.evaluate('document.getElementById("c").__m')
    assert_empty @h.errors, @h.error_report
  end

  # Turbo Drive back/forward restoration: after visiting B from A, popstate
  # (history.back/forward) triggers a restoration visit that swaps the cached
  # snapshot back in — no refetch — and restores the URL.
  def test_turbo_back_forward_restoration
    load_page("<!DOCTYPE html><html><head><title>A</title></head>" \
              "<body><p id='c'>PAGE-A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => {
      "status" => 200, "contentType" => "text/html",
      "body" => "<html><head><title>B</title></head><body><p id='c'>PAGE-B</p></body></html>"
    })

    @h.execute('Turbo.visit("/b");')
    @h.pump(rounds: 40)
    assert_equal "PAGE-B", @h.evaluate('document.getElementById("c").textContent')
    assert_equal "http://localhost/b", @h.evaluate("String(location.href)")

    @h.execute("history.back();")
    @h.pump(rounds: 60)
    assert_equal "http://localhost/", @h.evaluate("String(location.href)")
    assert_equal "PAGE-A", @h.evaluate('document.getElementById("c").textContent')

    @h.execute("history.forward();")
    @h.pump(rounds: 60)
    assert_equal "http://localhost/b", @h.evaluate("String(location.href)")
    assert_equal "PAGE-B", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
  end

  # Scroll restoration: Turbo records the scroll position (via the scroll event)
  # into the history entry and replays it on a back/forward restoration visit.
  # Dommy has no layout, but tracks a virtual scroll position so this is
  # observable: scrolling page A to y=300, navigating away, and going back
  # restores window.scrollY to 300 (an advance visit scrolls to the top).
  def test_turbo_scroll_restoration
    load_page("<!DOCTYPE html><html><head><title>A</title></head><body><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><head><title>B</title></head><body><p id='c'>B</p></body></html>" })
    @h.pump(rounds: 5)

    @h.execute("window.scrollTo(0, 300);")
    @h.pump(rounds: 5)
    assert_equal 300, @h.evaluate("window.scrollY")

    @h.execute('Turbo.visit("/b");')
    @h.pump(rounds: 40)
    assert_equal 0, @h.evaluate("window.scrollY") # advance visit scrolls to top

    @h.execute("history.back();")
    @h.pump(rounds: 60)
    assert_equal "A", @h.evaluate('document.getElementById("c").textContent')
    assert_equal 300, @h.evaluate("window.scrollY") # restored
    assert_empty @h.errors, @h.error_report
  end

  # Progress bar show/hide: Turbo installs a <style class=turbo-progress-bar> on
  # boot, and during a slow visit (past the 500ms delay) inserts a progress
  # <div class=turbo-progress-bar> into the DOM, then removes it when the visit
  # completes. No layout, but the element insert/remove is fully observable.
  def test_turbo_progress_bar_show_hide
    load_page("<!DOCTYPE html><html><head></head><body><p id='c'>A</p></body></html>")
    @h.pump(rounds: 5)
    # The stylesheet is installed on boot; no progress element is shown yet.
    assert_equal 1, @h.window.document.query_selector_all("style").size
    assert_equal 0, progress_bar_count

    # A slow response so the 500ms progress-bar delay elapses mid-visit.
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "delay" => 1500, "body" => "<html><head></head><body><p id='c'>B</p></body></html>" })
    @h.execute('Turbo.visit("/b");')

    # Past the 500ms delay but before the response → the bar is shown.
    @h.window.scheduler.advance_time(600)
    @h.runtime.drain_microtasks
    assert_equal 1, progress_bar_count

    # Let the response land and the fade-out timeout run → the bar is removed.
    @h.pump(rounds: 60, step_ms: 50)
    assert_equal "B", @h.evaluate('document.getElementById("c").textContent')
    assert_equal 0, progress_bar_count
    assert_empty @h.errors, @h.error_report
  end

  # <meta name="turbo-visit-control" content="reload"> on the destination page
  # makes Turbo do a full reload (turbo:reload) instead of a Drive render.
  def test_turbo_visit_control_reload
    load_page("<!DOCTYPE html><html><head></head><body><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><head><meta name='turbo-visit-control' content='reload'></head>" \
                "<body><p id='c'>B</p></body></html>" })
    @h.execute('globalThis.__reload = false; document.addEventListener("turbo:reload", () => globalThis.__reload = true);')
    @h.execute('Turbo.visit("/b");')
    @h.pump(rounds: 40)

    assert_equal true, @h.evaluate("globalThis.__reload")
    # Full reload, not a Drive render: the body was not swapped to B.
    assert_equal "A", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
  end

  # <meta name="turbo-root" content="/app"> scopes Drive to the root path: a link
  # inside the root is intercepted, a link outside is left to the browser.
  def test_turbo_root_scoping
    load_page("<!DOCTYPE html><html><head><meta name='turbo-root' content='/app'></head>" \
              "<body><a id='inside' href='/app/page'>in</a>" \
              "<a id='outside' href='/other'>out</a></body></html>")
    @h.stub_fetch(
      "http://localhost/app/page" => { "status" => 200, "contentType" => "text/html",
        "body" => "<html><head><meta name='turbo-root' content='/app'></head>" \
                  "<body><p id='c'>INSIDE</p></body></html>" },
      "http://localhost/other" => { "status" => 200, "contentType" => "text/html",
        "body" => "<html><body><p id='c'>OUTSIDE</p></body></html>" }
    )
    @h.execute('globalThis.__visits = 0; document.addEventListener("turbo:visit", () => globalThis.__visits++);')

    # A link inside the root is Drive-handled.
    @h.execute('document.getElementById("inside").click();')
    @h.pump(rounds: 40)
    assert_equal 1, @h.evaluate("globalThis.__visits")
    assert_equal "INSIDE", @h.evaluate('document.querySelector("#c").textContent')

    # A link outside the root is NOT intercepted (no further turbo:visit).
    @h.execute('var o = document.getElementById("outside"); if (o) o.click();')
    @h.pump(rounds: 40)
    assert_equal 1, @h.evaluate("globalThis.__visits")
    assert_empty @h.errors, @h.error_report
  end

  # turbo:before-visit is cancelable: preventDefault() aborts the visit (the
  # page is left untouched). Exercises the cancelable-event mechanism
  # (preventDefault → defaultPrevented, bubbling documentElement → document).
  def test_turbo_before_visit_is_cancelable
    load_page("<!DOCTYPE html><html><head></head><body><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><p id='c'>B</p></body></html>" })
    @h.execute(<<~JS)
      globalThis.__cancelable = null;
      document.addEventListener("turbo:before-visit", (e) => {
        globalThis.__cancelable = e.cancelable;
        e.preventDefault();
      });
    JS
    @h.execute('Turbo.visit("/b");')
    @h.pump(rounds: 40)

    assert_equal true, @h.evaluate("globalThis.__cancelable")
    assert_equal "A", @h.evaluate('document.getElementById("c").textContent') # visit canceled
    assert_empty @h.errors, @h.error_report
  end

  # The before-* lifecycle hooks fire with their detail payloads on a visit:
  # before-fetch-request (url + mutable fetchOptions.headers), before-cache, and
  # before-render (cancelable, detail.newBody + resume()).
  def test_turbo_before_hooks_payloads
    load_page("<!DOCTYPE html><html><head></head><body><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><p id='c'>B</p></body></html>" })
    @h.execute(<<~JS)
      globalThis.__h = {};
      document.addEventListener("turbo:before-fetch-request", (e) => {
        globalThis.__h.fetchUrl = e.detail && e.detail.url ? String(e.detail.url) : null;
        globalThis.__h.headers = !!(e.detail && e.detail.fetchOptions && e.detail.fetchOptions.headers);
      });
      document.addEventListener("turbo:before-cache", () => { globalThis.__h.cache = true; });
      document.addEventListener("turbo:before-render", (e) => {
        globalThis.__h.renderCancelable = e.cancelable;
        globalThis.__h.newBody = !!(e.detail && e.detail.newBody);
        globalThis.__h.resume = typeof (e.detail && e.detail.resume) === "function";
      });
    JS
    @h.execute('Turbo.visit("/b");')
    @h.pump(rounds: 40)

    assert_equal "http://localhost/b", @h.evaluate("globalThis.__h.fetchUrl")
    assert_equal true, @h.evaluate("globalThis.__h.headers")
    assert_equal true, @h.evaluate("globalThis.__h.cache")
    assert_equal true, @h.evaluate("globalThis.__h.renderCancelable")
    assert_equal true, @h.evaluate("globalThis.__h.newBody")
    assert_equal true, @h.evaluate("globalThis.__h.resume")
    assert_equal "B", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
  end

  # A morph dispatches per-element / per-attribute hooks
  # (turbo:before-morph-element, turbo:before-morph-attribute).
  def test_turbo_morph_hooks
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<div id='t'><p id='c' class='old'>OLD</p></div></body></html>")
    @h.execute(<<~JS)
      globalThis.__m = { el: 0, attr: 0 };
      document.addEventListener("turbo:before-morph-element", () => globalThis.__m.el++);
      document.addEventListener("turbo:before-morph-attribute", () => globalThis.__m.attr++);
    JS
    @h.execute('Turbo.renderStreamMessage(\'<turbo-stream action="replace" method="morph" target="t">' \
               '<template><div id="t"><p id="c" class="new">NEW</p></div></template></turbo-stream>\');')
    @h.pump(rounds: 20)

    assert_operator @h.evaluate("globalThis.__m.el"), :>=, 1
    assert_operator @h.evaluate("globalThis.__m.attr"), :>=, 1
    assert_equal "NEW", @h.window.document.get_element_by_id("c").text_content
    assert_equal "new", @h.window.document.get_element_by_id("c").get_attribute("class")
    assert_empty @h.errors, @h.error_report
  end

  # Turbo dispatches its form lifecycle events (turbo:submit-start/end wrap the
  # request; turbo:before-fetch-request/response wrap the fetch).
  def test_turbo_form_lifecycle_events
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<form id='frm' action='/s' method='post'><button>go</button></form></body></html>")
    @h.stub_fetch("http://localhost/s" => {
      "status" => 200, "contentType" => "text/vnd.turbo-stream.html",
      "body" => '<turbo-stream action="append" target="frm"><template><span>S</span></template></turbo-stream>'
    })
    @h.execute(<<~JS)
      globalThis.__ev = [];
      for (const n of ["turbo:submit-start", "turbo:before-fetch-request", "turbo:before-fetch-response", "turbo:submit-end"]) {
        document.addEventListener(n, () => globalThis.__ev.push(n));
      }
      document.getElementById("frm").requestSubmit();
    JS
    @h.pump(rounds: 40)

    events = @h.evaluate("globalThis.__ev")
    assert_includes events, "turbo:submit-start"
    assert_includes events, "turbo:submit-end"
    assert_includes events, "turbo:before-fetch-request"
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo-method turns a GET link into a non-GET request (DELETE here),
  # whose turbo-stream response is applied.
  def test_turbo_data_turbo_method
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<a id='lnk' href='/del' data-turbo-method='delete'>del</a><div id='m'></div></body></html>")
    @h.stub_fetch("http://localhost/del" => {
      "status" => 200, "contentType" => "text/vnd.turbo-stream.html",
      "body" => '<turbo-stream action="append" target="m"><template><i>D</i></template></turbo-stream>'
    })
    @h.execute('document.getElementById("lnk").click();')
    @h.pump(rounds: 40)

    assert_equal "DELETE", @h.evaluate("window.__last_init__.method")
    assert_equal "http://localhost/del", @h.evaluate("window.__last_url__")
    assert_equal "<i>D</i>", @h.window.document.get_element_by_id("m").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # A GET form (search form) navigates via Turbo Drive with the serialized
  # query string appended to the action.
  def test_turbo_get_form_navigation
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<form id='frm' action='/search' method='get'><input name='q' value='hi'><button>go</button></form>" \
              "<p id='c'>HOME</p></body></html>")
    @h.stub_fetch("http://localhost/search?q=hi" => {
      "status" => 200, "contentType" => "text/html",
      "body" => "<html><head><title>R</title></head><body><p id='c'>RESULTS</p></body></html>"
    })
    @h.execute('document.getElementById("frm").requestSubmit();')
    @h.pump(rounds: 40)

    assert_equal "RESULTS", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
  end

  # Turbo follows a redirected response: it renders the redirect body AND
  # updates history to the final (redirected) URL, not the requested one.
  def test_turbo_follows_redirect
    load_page("<!DOCTYPE html><html><head></head><body><a id='lnk' href='/old'>go</a><p id='c'>HOME</p></body></html>")
    @h.stub_fetch("http://localhost/old" => {
      "status" => 200, "contentType" => "text/html",
      "redirected" => true, "url" => "http://localhost/new",
      "body" => "<html><head><title>N</title></head><body><p id='c'>NEWPAGE</p></body></html>"
    })
    @h.execute('document.getElementById("lnk").click();')
    @h.pump(rounds: 40)

    assert_equal "NEWPAGE", @h.evaluate('document.getElementById("c").textContent')
    assert_equal "http://localhost/new", @h.evaluate("String(Turbo.session.history.location)")
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo-confirm prompts via window.confirm before issuing the request;
  # a truthy answer lets it proceed.
  def test_turbo_confirm_before_request
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<a id='lnk' href='/x' data-turbo-method='delete' data-turbo-confirm='Sure?'>del</a><div id='m'></div></body></html>")
    @h.stub_fetch("http://localhost/x" => {
      "status" => 200, "contentType" => "text/vnd.turbo-stream.html",
      "body" => '<turbo-stream action="append" target="m"><template><i>OK</i></template></turbo-stream>'
    })
    @h.execute(<<~JS)
      globalThis.__asked = [];
      globalThis.confirm = (msg) => { globalThis.__asked.push(msg); return true; };
      document.getElementById("lnk").click();
    JS
    @h.pump(rounds: 40)

    assert_equal ["Sure?"], @h.evaluate("globalThis.__asked")
    assert_equal "<i>OK</i>", @h.window.document.get_element_by_id("m").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # turbo-frame loading="lazy" defers its src fetch until revealed; switching to
  # loading="eager" loads it.
  def test_turbo_frame_lazy_loading
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<turbo-frame id='f' src='/frame' loading='lazy'>placeholder</turbo-frame></body></html>")
    @h.stub_fetch("http://localhost/frame" => {
      "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><turbo-frame id='f'>LAZY-LOADED</turbo-frame></body></html>"
    })
    @h.pump(rounds: 40)
    assert_equal "placeholder", @h.window.document.get_element_by_id("f").text_content.strip

    @h.execute('document.getElementById("f").setAttribute("loading", "eager");')
    @h.pump(rounds: 40)
    assert_equal "LAZY-LOADED", @h.window.document.get_element_by_id("f").text_content.strip
    assert_empty @h.errors, @h.error_report
  end

  # <turbo-stream-source src="/sse">: on connect Turbo opens an EventSource and
  # listens for "message" events; a pushed message whose data is a turbo-stream
  # is applied. We drive a server push by dispatching a MessageEvent to the
  # captured source.
  def test_turbo_stream_source_sse
    load_page("<!DOCTYPE html><html><head></head><body><div id='list'></div></body></html>")
    push_stream_via_source("/sse", "EventSource", "<p>SSE-MSG</p>")
    assert_equal "<p>SSE-MSG</p>", list_html
    assert_empty @h.errors, @h.error_report
  end

  # A ws:// source uses WebSocket instead of EventSource; same message delivery.
  def test_turbo_stream_source_websocket
    load_page("<!DOCTYPE html><html><head></head><body><div id='list'></div></body></html>")
    push_stream_via_source("ws://localhost/cable", "WebSocket", "<p>WS-MSG</p>")
    assert_equal "<p>WS-MSG</p>", list_html
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo-permanent: an element with [id][data-turbo-permanent] keeps its
  # node (and JS state) across a Drive navigation while the rest of the page is
  # replaced. (Exercises Node.contains, which Turbo's Bardo uses.)
  def test_turbo_permanent_element
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<div id='flash' data-turbo-permanent>KEEP</div><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><div id='flash' data-turbo-permanent>IGNORED</div><p id='c'>B</p></body></html>" })
    @h.execute('globalThis.__f = document.getElementById("flash"); globalThis.__f.__m = "STATE";')
    @h.execute('Turbo.visit("/b");')
    @h.pump(rounds: 40)

    assert_equal "B", @h.evaluate('document.getElementById("c").textContent')
    assert_equal "KEEP", @h.evaluate('document.getElementById("flash").textContent')
    assert_equal true, @h.evaluate('globalThis.__f === document.getElementById("flash")')
    assert_equal "STATE", @h.evaluate('document.getElementById("flash").__m')
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo="false" opts a link out of Turbo Drive — the click is not
  # intercepted (no turbo:visit), so the page is left to a normal navigation.
  def test_turbo_false_opt_out
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<a id='lnk' href='/b' data-turbo='false'>x</a><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><p id='c'>B</p></body></html>" })
    @h.execute('globalThis.__visited = false; document.addEventListener("turbo:visit", () => globalThis.__visited = true);')
    @h.execute('document.getElementById("lnk").click();')
    @h.pump(rounds: 40)

    assert_equal false, @h.evaluate("globalThis.__visited")
    assert_equal "A", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
  end

  # Apps can register custom stream actions on Turbo.StreamActions.
  def test_turbo_custom_stream_action
    load_page("<!DOCTYPE html><html><head></head><body><div id='t'>orig</div></body></html>")
    @h.execute(<<~JS)
      Turbo.StreamActions.shout = function () {
        this.targetElements.forEach((el) => { el.textContent = (this.getAttribute("word") || "").toUpperCase(); });
      };
    JS
    @h.execute('Turbo.renderStreamMessage(\'<turbo-stream action="shout" target="t" word="hi"></turbo-stream>\');')
    @h.pump(rounds: 10)

    assert_equal "HI", @h.window.document.get_element_by_id("t").text_content
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo-action="replace" makes the visit replace the history entry
  # instead of advancing it (history length stays the same).
  def test_turbo_action_replace
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<a id='lnk' href='/b' data-turbo-action='replace'>x</a></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><p id='c'>B</p></body></html>" })
    before = @h.evaluate("history.length")
    @h.execute('globalThis.__act = null; document.addEventListener("turbo:visit", (e) => globalThis.__act = e.detail && e.detail.action);')
    @h.execute('document.getElementById("lnk").click();')
    @h.pump(rounds: 40)

    assert_equal "replace", @h.evaluate("globalThis.__act")
    assert_equal before, @h.evaluate("history.length")
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo="false" on an ANCESTOR container opts every descendant link out of
  # Drive; a nested data-turbo="true" re-enables it (the nearest [data-turbo]
  # ancestor wins, via Turbo's findClosestRecursively → closest).
  def test_turbo_false_on_ancestor_container
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<div data-turbo='false'>" \
              "<a id='off' href='/b'>off</a>" \
              "<a id='on' href='/b' data-turbo='true'>on</a>" \
              "</div><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><p id='c'>B</p></body></html>" })
    @h.execute('globalThis.__v = 0; document.addEventListener("turbo:visit", () => globalThis.__v++);')

    # Inside the data-turbo="false" container → not intercepted.
    @h.execute('document.getElementById("off").click();')
    @h.pump(rounds: 40)
    assert_equal 0, @h.evaluate("globalThis.__v")
    assert_equal "A", @h.evaluate('document.getElementById("c").textContent')

    # The re-enabled link IS intercepted.
    @h.execute('var on = document.getElementById("on"); if (on) on.click();')
    @h.pump(rounds: 40)
    assert_equal 1, @h.evaluate("globalThis.__v")
    assert_equal "B", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
  end

  # A form with data-turbo="false" submits normally (Turbo doesn't intercept it).
  def test_turbo_form_opt_out
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<form id='frm' action='/s' method='post' data-turbo='false'><button>go</button></form>" \
              "<div id='m'></div></body></html>")
    @h.stub_fetch("http://localhost/s" => { "status" => 200, "contentType" => "text/vnd.turbo-stream.html",
      "body" => '<turbo-stream action="append" target="m"><template><i>S</i></template></turbo-stream>' })
    @h.execute('globalThis.__ss = 0; document.addEventListener("turbo:submit-start", () => globalThis.__ss++);')
    @h.execute('document.getElementById("frm").requestSubmit();')
    @h.pump(rounds: 40)

    assert_equal 0, @h.evaluate("globalThis.__ss")
    assert_equal "", @h.window.document.get_element_by_id("m").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo-action="replace" on a FORM (not just links) replaces history.
  def test_turbo_form_action_replace
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<form id='frm' action='/search' method='get' data-turbo-action='replace'>" \
              "<input name='q' value='hi'><button>go</button></form><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/search?q=hi" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><body><p id='c'>RESULTS</p></body></html>" })
    before = @h.evaluate("history.length")
    @h.execute('globalThis.__act = null; document.addEventListener("turbo:visit", (e) => globalThis.__act = e.detail && e.detail.action);')
    @h.execute('document.getElementById("frm").requestSubmit();')
    @h.pump(rounds: 40)

    assert_equal "replace", @h.evaluate("globalThis.__act")
    assert_equal before, @h.evaluate("history.length")
    assert_equal "RESULTS", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo-method supports verbs beyond delete (here PATCH).
  def test_turbo_method_patch
    load_page("<!DOCTYPE html><html><head></head><body>" \
              "<a id='lnk' href='/u' data-turbo-method='patch'>u</a><div id='m'></div></body></html>")
    @h.stub_fetch("http://localhost/u" => { "status" => 200, "contentType" => "text/vnd.turbo-stream.html",
      "body" => '<turbo-stream action="append" target="m"><template><i>P</i></template></turbo-stream>' })
    @h.execute('document.getElementById("lnk").click();')
    @h.pump(rounds: 40)

    assert_equal "PATCH", @h.evaluate("window.__last_init__.method")
    assert_equal "<i>P</i>", @h.window.document.get_element_by_id("m").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo-track="reload": when the tracked <head> assets differ between the
  # current page and the navigation response, Turbo forces a full reload (fires
  # turbo:reload) instead of a Drive render.
  def test_turbo_track_reload_on_asset_change
    load_page("<!DOCTYPE html><html><head>" \
              "<script src='/app-v1.js' data-turbo-track='reload'></script></head>" \
              "<body><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><head><script src='/app-v2.js' data-turbo-track='reload'></script></head>" \
                "<body><p id='c'>B</p></body></html>" })
    @h.execute('globalThis.__reload = false; document.addEventListener("turbo:reload", () => globalThis.__reload = true);')
    @h.execute('Turbo.visit("/b");')
    @h.pump(rounds: 40)

    assert_equal true, @h.evaluate("globalThis.__reload")
    # A full reload, not a Drive render: the body was not swapped to B.
    assert_equal "A", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
  end

  # Matching tracked assets → a normal Drive render (no reload).
  def test_turbo_track_no_reload_when_assets_match
    load_page("<!DOCTYPE html><html><head>" \
              "<script src='/app-v1.js' data-turbo-track='reload'></script></head>" \
              "<body><p id='c'>A</p></body></html>")
    @h.stub_fetch("http://localhost/b" => { "status" => 200, "contentType" => "text/html",
      "body" => "<html><head><script src='/app-v1.js' data-turbo-track='reload'></script></head>" \
                "<body><p id='c'>B</p></body></html>" })
    @h.execute('globalThis.__reload = false; document.addEventListener("turbo:reload", () => globalThis.__reload = true);')
    @h.execute('Turbo.visit("/b");')
    @h.pump(rounds: 40)

    assert_equal false, @h.evaluate("globalThis.__reload")
    assert_equal "B", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
  end

  # data-turbo-preload: a link with the attribute is fetched and its snapshot
  # cached on session start, so a later visit is served from cache without a
  # second fetch.
  def test_turbo_preload
    load_page(
      "<!DOCTYPE html><html><head></head><body>" \
      "<a id='lnk' href='/preloaded' data-turbo-preload>go</a><p id='c'>HOME</p></body></html>",
      fetch_stub: { "http://localhost/preloaded" => {
        "status" => 200, "contentType" => "text/html",
        "body" => "<html><head></head><body><p id='c'>PRELOADED</p></body></html>"
      } }
    )
    @h.pump(rounds: 40)

    keys = @h.evaluate(
      "(() => { const c = Turbo.session.navigator.view.snapshotCache; " \
      "return c.snapshots ? Object.keys(c.snapshots) : []; })()"
    )
    assert_includes keys, "http://localhost/preloaded"
    fetch_count = @h.window.__js_get__("__fetch_count__")

    # Visiting the preloaded link renders from the cached snapshot.
    @h.execute('document.getElementById("lnk").click();')
    @h.pump(rounds: 40)
    assert_equal "PRELOADED", @h.evaluate('document.getElementById("c").textContent')
    assert_empty @h.errors, @h.error_report
    # The snapshot was already in cache from preload (a fetch happened on load).
    assert_operator fetch_count, :>=, 1
  end

  private

  # Connect a <turbo-stream-source src=...>, capturing the EventSource/WebSocket
  # it opens, then dispatch a "message" MessageEvent carrying a turbo-stream that
  # appends `inner` to #list — mimicking a server push.
  def push_stream_via_source(src, source_ctor, inner)
    @h.execute(<<~JS)
      globalThis.__src = [];
      const _C = globalThis.#{source_ctor};
      globalThis.#{source_ctor} = function (url, opts) { const c = new _C(url, opts); globalThis.__src.push(c); return c; };
      const el = document.createElement("turbo-stream-source");
      el.setAttribute("src", #{src.inspect});
      document.body.appendChild(el);
    JS
    @h.pump(rounds: 10)
    @h.execute(
      "globalThis.__src[0].dispatchEvent(new MessageEvent('message', { data: " \
      "'<turbo-stream action=\"append\" target=\"list\"><template>#{inner}</template></turbo-stream>' }));"
    )
    @h.pump(rounds: 10)
  end

  def list_html
    @h.window.document.get_element_by_id("list").inner_html
  end

  # The progress <div> Turbo inserts/removes when showing/hiding the bar (the
  # <style> with the same class is matched by `style.turbo-progress-bar`, not
  # this element-class selector).
  def progress_bar_count
    @h.window.document.query_selector_all("div.turbo-progress-bar").size
  end
end
