# frozen_string_literal: true

require "test_helper"

# Dommy::Browser interaction (Phase 2): Capybara-vocabulary verbs drive JS
# handlers via real browser event sequences, plus deterministic time control.
class Dommy::Js::TestBrowserInteraction < Minitest::Test
  def test_click_drives_a_js_click_handler
    html = <<~HTML
      <html><body><button id="b">off</button><script>
        document.getElementById("b").addEventListener("click", (e) => {
          e.currentTarget.classList.add("is-on");
          e.currentTarget.textContent = "on";
        });
      </script></body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      b.click("#b")
      assert b.has_css?("button.is-on")
      assert b.has_text?("on")
    end
  end

  def test_fill_in_fires_input_and_change
    html = <<~HTML
      <html><body>
        <label for="email">Email</label><input id="email">
        <span id="out"></span>
        <script>
          const out = document.getElementById("out");
          const input = document.getElementById("email");
          input.addEventListener("input", (e) => { out.dataset.input = e.target.value; });
          input.addEventListener("change", (e) => { out.dataset.change = e.target.value; });
        </script>
      </body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      b.fill_in("Email", with: "a@example.com")
      assert_equal "a@example.com", b.evaluate('document.getElementById("out").dataset.input')
      assert_equal "a@example.com", b.evaluate('document.getElementById("out").dataset.change')
    end
  end

  # A React-style controlled input: a value tracker reads the field on input and
  # must observe the new value (the value is written via the native path).
  def test_fill_in_is_seen_by_a_value_tracker
    html = <<~HTML
      <html><body><input id="f"><script>
        window.__seen = [];
        document.getElementById("f").addEventListener("input", (e) => window.__seen.push(e.target.value));
      </script></body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      b.fill_in("f", with: "hello")
      assert_equal ["hello"], b.evaluate("window.__seen")
    end
  end

  def test_check_and_choose_and_select_fire_change
    html = <<~HTML
      <html><body>
        <input type="checkbox" id="agree">
        <input type="radio" name="g" id="r1"><input type="radio" name="g" id="r2">
        <select id="country"><option>Japan</option><option>France</option></select>
        <span id="log"></span>
        <script>
          const log = document.getElementById("log");
          const rec = (id) => document.getElementById(id).addEventListener("change", (e) => {
            log.textContent += id + ":" + (e.target.value ?? e.target.checked) + ";";
          });
          ["agree","r2","country"].forEach(rec);
        </script>
      </body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      b.check("agree")
      b.choose("r2")
      b.select("France", from: "country")
      log = b.evaluate('document.getElementById("log").textContent')
      assert_includes log, "agree:"
      assert_includes log, "r2:"
      assert_includes log, "country:"
      assert_equal "France", b.evaluate('document.getElementById("country").value')
    end
  end

  def test_click_button_dispatches_submit
    html = <<~HTML
      <html><body>
        <form id="f"><button type="submit">Save</button></form>
        <span id="out"></span>
        <script>
          document.getElementById("f").addEventListener("submit", (e) => {
            e.preventDefault();
            document.getElementById("out").textContent = "submitted";
          });
        </script>
      </body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      b.click_button("Save")
      assert_equal "submitted", b.evaluate('document.getElementById("out").textContent')
    end
  end

  def test_settle_flushes_raf_but_advance_time_needed_for_debounce
    html = <<~HTML
      <html><body><span id="raf"></span><span id="deb"></span><script>
        requestAnimationFrame(() => { document.getElementById("raf").textContent = "framed"; });
        setTimeout(() => { document.getElementById("deb").textContent = "debounced"; }, 300);
      </script></body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      b.settle
      assert_equal "framed", b.evaluate('document.getElementById("raf").textContent'), "settle flushes rAF"
      assert_equal "", b.evaluate('document.getElementById("deb").textContent'), "settle must NOT fire a 300ms timer"
      b.advance_time(300)
      assert_equal "debounced", b.evaluate('document.getElementById("deb").textContent')
    end
  end

  def test_local_storage_persists_within_the_browser
    Dommy::Browser.open("<html><body></body></html>") do |b|
      b.execute('localStorage.setItem("k", "v");')
      assert_equal "v", b.evaluate('localStorage.getItem("k")')
    end
  end

  def test_url_and_form_data_globals_available
    html = '<html><body><form id="f"><input name="a" value="1"></form></body></html>'
    Dommy::Browser.open(html) do |b|
      assert_equal "/p", b.evaluate('new URL("http://x.test/p?q=1").pathname')
      assert_equal "1", b.evaluate('new URLSearchParams("q=1").get("q")')
      assert_equal "1", b.evaluate('new FormData(document.getElementById("f")).get("a")')
    end
  end

  # End-to-end: a Stimulus-like controller wired by data-action toggles a class.
  def test_end_to_end_action_toggle
    html = <<~HTML
      <html><body>
        <div data-controller="t"><button data-action="click->t#toggle">x</button><p data-t-target="box">box</p></div>
        <script>
          // tiny controller registry keyed off data-action
          document.querySelectorAll("[data-action]").forEach((el) => {
            el.addEventListener("click", () => {
              el.closest("[data-controller]").querySelector("[data-t-target]").classList.toggle("is-on");
            });
          });
        </script>
      </body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      refute b.has_css?(".is-on")
      b.click("button")
      assert b.has_css?("p.is-on")
    end
  end
end
