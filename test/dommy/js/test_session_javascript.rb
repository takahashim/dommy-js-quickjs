# frozen_string_literal: true

require "test_helper"
require "dommy/js/quickjs/rack"

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
end
