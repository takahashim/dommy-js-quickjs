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
  # the default page set up above.
  def load_page(html)
    @h&.dispose
    @h = Dommy::Js::BrowserHarness.new(html)
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
end
