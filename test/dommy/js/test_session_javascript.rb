# frozen_string_literal: true

require "test_helper"

# dommy-rack isn't published yet, so it's only on the load path inside the
# dommy monorepo. In a standalone clone (e.g. CI), skip this file rather than
# aborting the whole suite at load time.
begin
  require "dommy/js/quickjs/rack"
rescue LoadError
  warn "skipping test_session_javascript.rb: dommy-rack not available"
  return
end

# Dommy::Rack::Session.new(app, javascript: true) — Phase 3 Rails integration
# engine: page <script>s boot on navigation, interaction verbs drive JS, and
# fetch resolves through the same Rack app (shared cookie jar).
class Dommy::Js::TestSessionJavascript < Minitest::Test
  APP = lambda do |env|
    case env["PATH_INFO"]
    when "/app.js"
      [200, {"content-type" => "application/javascript"}, [<<~JS]]
        document.querySelector("#btn").addEventListener("click", (e) => {
          e.currentTarget.closest("body").querySelector("#box").classList.add("is-on");
        });
      JS
    when "/api/ping"
      [200, {"content-type" => "text/plain"}, ["pong"]]
    when "/set-cookie"
      [200, {"content-type" => "text/plain", "Set-Cookie" => "u=alice"}, ["set"]]
    when "/whoami"
      [200, {"content-type" => "text/plain"}, [env["HTTP_COOKIE"].to_s]]
    when "/onload"
      [200, {"content-type" => "text/html"},
       ['<html><body><script>setTimeout(() => { window.__t = "fired"; }, 0);</script></body></html>']]
    when "/target"
      [200, {"content-type" => "text/html"}, ["<html><body><h1 id='target'>TARGET</h1></body></html>"]]
    when "/echo"
      [200, {"content-type" => "text/html"}, ["<html><body><h1 id='m'>#{env["REQUEST_METHOD"]}</h1></body></html>"]]
    when "/delform"
      [200, {"content-type" => "text/html"}, [<<~HTML]]
        <html><body><form id="df" action="/echo" method="post">
          <input type="hidden" name="_method" value="delete">
        </form></body></html>
      HTML
    when "/nav"
      [200, {"content-type" => "text/html"}, [<<~HTML]]
        <html><body>
          <a id="lnk" href="/target">link</a>
          <form id="frm" action="/target" method="get">
            <input type="hidden" name="x" value="1">
            <button id="sub" type="submit">submit</button>
          </form>
          <button id="jsloc">jsloc</button>
          <button id="inlinenav" onclick="window.location = '/target'">inline</button>
        </body></html>
      HTML
    else
      [200, {"content-type" => "text/html"}, [<<~HTML]]
        <html><head><meta name="csrf-token" content="tok123"></head>
        <body>
          <button id="btn">go</button><p id="box">box</p>
          <script src="/app.js"></script>
          <script>
            document.addEventListener("DOMContentLoaded", () => { window.__ready = true; });
          </script>
        </body></html>
      HTML
    end
  end

  def session(**opts) = Dommy::Rack::Session.new(APP, javascript: true, **opts)

  def teardown
    @session&.dispose_js
  end

  def test_javascript_predicate
    @session = session
    assert @session.javascript?
    refute Dommy::Rack::Session.new(APP).javascript?
  end

  def test_page_scripts_boot_and_lifecycle_fires
    @session = session
    @session.visit("/")
    assert_equal true, @session.evaluate_script("window.__ready"), "DOMContentLoaded fired"
  end

  def test_interaction_drives_js_handler
    @session = session
    @session.visit("/")
    refute @session.has_css?("#box.is-on")
    @session.click("#btn")
    assert @session.has_css?("#box.is-on"), "the page's click handler ran"
  end

  def test_visit_settles_by_default_and_can_opt_out
    @session = session

    # settle: false leaves the due-now timer pending, so __t is never assigned —
    # an absent property reads as JS `undefined`.
    @session.visit("/onload", settle: false)
    assert_equal "undefined", @session.evaluate_script("typeof window.__t"),
      "settle: false observes the page mid-flight (timer not yet fired)"

    # The default settles the page: the setTimeout(0) has fired.
    @session.visit("/onload")
    assert_equal "fired", @session.evaluate_script("window.__t")
  end

  def test_execute_and_evaluate_script
    @session = session
    @session.visit("/")
    @session.execute_script('document.getElementById("box").textContent = "changed";')
    assert_equal "changed", @session.evaluate_script('document.getElementById("box").textContent')
  end

  def test_fetch_resolves_through_the_rack_app
    @session = session
    @session.visit("/")
    @session.execute_script('fetch("/api/ping").then((r) => r.text()).then((t) => { window.__fetched = t; });')
    @session.settle
    assert_equal "pong", @session.evaluate_script("window.__fetched")
  end

  def test_fetch_shares_the_session_cookie_jar
    @session = session
    @session.visit("/set-cookie")    # sets cookie u=alice into the session jar
    @session.visit("/")
    # window.fetch goes through the Rack app and carries the session's cookies.
    @session.execute_script('fetch("/whoami").then((r) => r.text()).then((t) => { window.__seen = t; });')
    @session.settle
    assert_includes @session.evaluate_script("window.__seen"), "u=alice"
  end

  def test_csrf_meta_is_readable_by_js
    @session = session
    @session.visit("/")
    token = @session.evaluate_script('document.querySelector("meta[name=csrf-token]").content')
    assert_equal "tok123", token
  end

  def test_js_methods_raise_without_javascript_mode
    plain = Dommy::Rack::Session.new(APP)
    err = assert_raises(Dommy::Rack::Error) { plain.execute_script("1") }
    assert_includes err.message, "javascript: true"
  end

  # --- N4-2: page-initiated navigation routes through the delegate ---

  # These exercise the real JS runtime (the suite otherwise leans on NullRuntime),
  # so they cover the seam that lets a page navigate itself: location.href= /
  # window.location= / form.submit() reach the session and load a new document.

  def test_js_location_href_navigates
    @session = session
    @session.visit("/nav")
    @session.execute_script("location.href = '/target'")
    @session.settle
    assert_match(%r{/target\z}, @session.current_url)
    assert @session.has_css?("#target"), "the new document loaded"
  end

  def test_js_window_location_string_navigates
    @session = session
    @session.visit("/nav")
    @session.execute_script("window.location = '/target'")
    @session.settle
    assert_match(%r{/target\z}, @session.current_url)
    assert @session.has_css?("#target")
  end

  def test_js_form_submit_navigates_with_query
    @session = session
    @session.visit("/nav")
    @session.execute_script("document.getElementById('frm').submit()")
    @session.settle
    assert_match(%r{/target\?x=1\z}, @session.current_url)
    assert @session.has_css?("#target")
  end

  def test_click_link_navigates_via_activation
    @session = session
    @session.visit("/nav")
    @session.click("#lnk")
    assert_match(%r{/target\z}, @session.current_url)
    assert @session.has_css?("#target")
  end

  def test_click_submit_button_navigates_via_activation
    @session = session
    @session.visit("/nav")
    @session.click("#sub")
    assert_match(%r{/target\?x=1\z}, @session.current_url)
    assert @session.has_css?("#target")
  end

  def test_click_handler_that_sets_location_navigates
    @session = session
    @session.visit("/nav")
    # A JS click handler that navigates programmatically (a common pattern) —
    # the deferred delegate performs it after the handler returns.
    @session.execute_script(
      "document.getElementById('jsloc').addEventListener('click', () => { window.location = '/target'; })"
    )
    @session.click("#jsloc")
    assert_match(%r{/target\z}, @session.current_url)
    assert @session.has_css?("#target")
  end

  def test_inline_onclick_handler_navigates
    @session = session
    @session.visit("/nav")
    # <button onclick="window.location = '/target'"> — inline handler compiled at
    # boot, its navigation performed by the delegate.
    @session.click("#inlinenav")
    assert_match(%r{/target\z}, @session.current_url)
    assert @session.has_css?("#target")
  end

  def test_location_replace_overwrites_the_current_history_entry
    @session = session
    @session.visit("/")
    @session.execute_script("location.assign('/nav')")
    @session.settle
    @session.execute_script("location.replace('/target')")
    @session.settle

    assert_match(%r{/target\z}, @session.current_url)
    # /nav was replaced by /target, so back returns to "/", not /nav.
    @session.back
    assert_match(%r{example\.org/\z}, @session.current_url)
  end

  def test_form_method_override_applies_on_the_delegate_path
    @session = session
    @session.visit("/delform")
    @session.execute_script("document.getElementById('df').submit()")
    @session.settle
    # POST + hidden _method=delete becomes a real DELETE (the session applies
    # the override, so it works even without Rack::MethodOverride in the app).
    assert_equal "DELETE", @session.find("#m").text_content
  end

  # --- Off-thread network: an injected executor defers fetch to a worker ---

  # Captures submitted jobs so a test runs them deterministically; #run_all runs
  # each on a real worker thread (proving the request leaves the page thread) and
  # joins before handing the result back, mirroring dommynx's NetworkPool.
  class ManualExecutor
    attr_reader :pending

    def initialize = @pending = []
    def submit(job, &on_result) = (@pending << [job, on_result]) && self

    def run_all
      @pending.each do |job, on_result|
        Thread.new { on_result.call(begin; job.call; rescue StandardError; nil; end) }.join
      end
      @pending.clear
    end
  end

  def test_fetch_runs_off_thread_through_an_injected_executor
    executor = ManualExecutor.new
    @session = session(network_executor: executor)
    @session.visit("/")

    @session.execute_script('fetch("/api/ping").then((r) => r.text()).then((t) => { window.__fetched = t; });')

    # Deferred to the executor, not resolved inline: the promise is still pending.
    assert_equal "undefined", @session.evaluate_script("typeof window.__fetched")
    refute_empty executor.pending, "the request was handed to the network executor"

    executor.run_all          # a worker thread performs the request off the page thread
    @session.advance_time(0)  # the response is applied on the page thread via the inbox

    assert_equal "pong", @session.evaluate_script("window.__fetched")
  end

  def test_off_thread_fetch_carries_the_session_cookies
    executor = ManualExecutor.new
    @session = session(network_executor: executor)
    @session.visit("/set-cookie") # u=alice into the shared jar
    @session.visit("/")

    @session.execute_script('fetch("/whoami").then((r) => r.text()).then((t) => { window.__seen = t; });')
    executor.run_all
    @session.advance_time(0)

    assert_includes @session.evaluate_script("window.__seen"), "u=alice"
  end
end

# Browser globals frameworks read bare (without `window.`) are aliased onto the
# global scope (regression: `performance.now()` threw "performance is not
# defined" because only a subset was aliased).
class Dommy::Js::TestBareGlobals < Minitest::Test
  APP = ->(_env) { [200, {"content-type" => "text/html"}, ["<!DOCTYPE html><html><body></body></html>"]] }

  def test_bare_browser_globals_resolve_on_global_scope
    s = Dommy::Rack::Session.new(APP, javascript: true)
    s.visit("/")
    assert_equal "object", s.evaluate_script("typeof performance")
    assert_equal "number", s.evaluate_script("typeof performance.now()")
    assert_equal "object", s.evaluate_script("typeof crypto")
    assert_equal "function", s.evaluate_script("typeof structuredClone")
    assert_equal '{"a":1}', s.evaluate_script("JSON.stringify(structuredClone({a:1}))")
    assert_equal "aGk=", s.evaluate_script("btoa('hi')") # bare btoa works (no proxy cycle)
    assert_equal "hi", s.evaluate_script("atob('aGk=')")
    # window methods that previously cycled into a stack overflow when aliased:
    assert_equal false, s.evaluate_script("confirm('ok?')")
    assert_equal "function", s.evaluate_script("typeof getSelection().toString")
    assert_equal "object", s.evaluate_script("typeof open('about:blank')") # null -> no new window, no recursion
  ensure
    s&.dispose_js
  end

  # This QuickJS build ships without ICU; without a polyfill any `Intl.*` use
  # throws "'Intl' is not defined" (nuxt.com, i18n libs). The polyfill formats
  # reasonably so pages run.
  def test_intl_polyfill
    s = Dommy::Rack::Session.new(APP, javascript: true)
    s.visit("/")
    assert_equal "object", s.evaluate_script("typeof Intl")
    assert_equal "1,234,567.89", s.evaluate_script('new Intl.NumberFormat("en").format(1234567.89)')
    assert_equal "42%", s.evaluate_script('new Intl.NumberFormat("en",{style:"percent"}).format(0.42)')
    assert_equal "string", s.evaluate_script('typeof new Intl.DateTimeFormat("en").format(0)')
    assert_equal "a, b, c", s.evaluate_script('new Intl.ListFormat("en").format(["a","b","c"])')
    assert_equal "one", s.evaluate_script('new Intl.PluralRules("en").select(1)')
    assert_equal "-3 days", s.evaluate_script('new Intl.RelativeTimeFormat("en").format(-3,"day")')
  ensure
    s&.dispose_js
  end

  # No WebAssembly in this build; a bare `WebAssembly.foo` reference threw
  # "'WebAssembly' is not defined". The stub makes it defined (so feature probes
  # / references don't crash) while compile/instantiate reject and validate()
  # is false, so WASM-loading code takes its JS fallback.
  def test_webassembly_stub
    s = Dommy::Rack::Session.new(APP, javascript: true)
    s.visit("/")
    assert_equal "object", s.evaluate_script("typeof WebAssembly")
    assert_equal false, s.evaluate_script("WebAssembly.validate(new Uint8Array([0]))")
    assert_equal "function", s.evaluate_script("typeof WebAssembly.instantiate")
    # Memory honors {shared:true} so WPT's common/sab.js keeps deriving SharedArrayBuffer.
    assert_equal "SharedArrayBuffer",
      s.evaluate_script("new WebAssembly.Memory({initial:1,shared:true}).buffer.constructor.name")
  ensure
    s&.dispose_js
  end

  # Absent properties read as JS `undefined` with `in` false (not null) across
  # the DOM surface — vue-meta on note.com does `isUndefined(window.Vue) ||
  # install(window.Vue)`; null made it call install(null) and crash.
  def test_absent_properties_are_undefined_and_not_in
    body = "<!DOCTYPE html><html><body><div id=\"x\"></div></body></html>"
    s = Dommy::Rack::Session.new(->(_e) { [200, {"content-type" => "text/html"}, [body]] }, javascript: true)
    s.visit("/")
    # window
    assert_equal "undefined", s.evaluate_script("typeof window.Vue")
    assert_equal false, s.evaluate_script("'Vue' in window")
    # element / navigator / document
    assert_equal "undefined", s.evaluate_script("typeof document.getElementById('x').nope")
    assert_equal false, s.evaluate_script("'nope' in document.getElementById('x')")
    assert_equal "undefined", s.evaluate_script("typeof navigator.bogusApi")
    assert_equal "undefined", s.evaluate_script("typeof document.bogusProp")
    # window <-> globalThis sharing still works (set on one, read on the other)
    s.execute_script("window.__shared = 1")
    assert_equal 1, s.evaluate_script("globalThis.__shared")
    s.execute_script("globalThis.__shared2 = 2")
    assert_equal 2, s.evaluate_script("window.__shared2")
    # present-but-null stays null (not undefined): an empty element's firstChild
    assert_equal "object", s.evaluate_script("typeof document.getElementById('x').firstChild")
    assert_equal true, s.evaluate_script("document.getElementById('x').firstChild === null")
  ensure
    s&.dispose_js
  end

  def test_post_message_delivers_a_message_event_to_self
    s = Dommy::Rack::Session.new(APP, javascript: true)
    s.visit("/")
    s.evaluate_script("globalThis.__pm = ''; addEventListener('message', (e) => { globalThis.__pm = e.data });")
    s.evaluate_script("postMessage('payload')")
    s.settle
    assert_equal "payload", s.evaluate_script("globalThis.__pm")
  ensure
    s&.dispose_js
  end
end
