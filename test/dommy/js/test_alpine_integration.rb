# frozen_string_literal: true

require "test_helper"

# Drives the *real* Alpine.js 3 bundle on Dommy + QuickJS. Alpine is declarative
# and attribute-driven (x-data/x-text/x-on/x-model/x-show/x-if), initialized by
# scanning the DOM and backed by Proxy reactivity — close in spirit to Stimulus,
# and popular alongside Rails. Skips unless the bundle is vendored:
#   curl -sL https://unpkg.com/alpinejs@3/dist/cdn.min.js -o test/fixtures/alpine.umd.js
#
# Alpine auto-starts when loaded (the document is already "complete"), so the
# x-* markup must be in the page before the bundle is loaded. The fixture must
# also be set up before load_script.
class Dommy::Js::TestAlpineIntegration < Minitest::Test
  BUNDLE = File.expand_path("../../fixtures/alpine.umd.js", __dir__)

  def setup
    skip "Alpine bundle not vendored (#{BUNDLE})" unless File.exist?(BUNDLE)
  end

  def teardown
    @h&.dispose
  end

  # Build the page with x-* markup, then load+start Alpine over it.
  def boot(body_html)
    @h = Dommy::Js::BrowserHarness.new("<!DOCTYPE html><html><head></head><body>#{body_html}</body></html>")
    @h.load_script(BUNDLE)
    @h.pump(rounds: 20)
    @h
  end

  def doc = @h.window.document

  # x-text renders state (incl. a getter), x-on:click mutates it, x-show toggles
  # display, and x-model two-way-binds an input — all reactively.
  def test_core_directives
    boot(<<~HTML)
      <div x-data="{ count: 0, name: 'hi', get doubled() { return this.count * 2; } }">
        <span id="c" x-text="count"></span>
        <span id="d" x-text="doubled"></span>
        <button id="inc" x-on:click="count++">+</button>
        <input id="m" x-model="name">
        <span id="echo" x-text="name"></span>
        <p id="big" x-show="count > 1">big</p>
      </div>
    HTML
    assert_equal "0", doc.get_element_by_id("c").text_content
    assert_equal "0", doc.get_element_by_id("d").text_content
    assert_equal "hi", doc.get_element_by_id("echo").text_content
    assert_equal "none", @h.evaluate("document.getElementById('big').style.display")

    @h.execute("document.getElementById('inc').click();")
    @h.pump(rounds: 20)
    @h.execute("document.getElementById('inc').click();")
    @h.pump(rounds: 20)
    assert_equal "2", doc.get_element_by_id("c").text_content
    assert_equal "4", doc.get_element_by_id("d").text_content
    assert_equal "", @h.evaluate("document.getElementById('big').style.display")

    @h.execute(<<~JS)
      const i = document.getElementById('m');
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(i, 'world');
      i.dispatchEvent(new Event('input', { bubbles: true }));
    JS
    @h.pump(rounds: 20)
    assert_equal "world", doc.get_element_by_id("echo").text_content
    assert_empty @h.errors, @h.error_report
  end

  # x-if conditionally renders (and removes) its <template> contents.
  def test_x_if
    boot(<<~HTML)
      <div x-data="{ show: true }">
        <button id="t" x-on:click="show = !show">toggle</button>
        <template x-if="show"><span id="cond">SHOWN</span></template>
      </div>
    HTML
    refute_nil doc.get_element_by_id("cond")

    @h.execute("document.getElementById('t').click();")
    @h.pump(rounds: 20)
    assert_nil doc.get_element_by_id("cond")

    @h.execute("document.getElementById('t').click();")
    @h.pump(rounds: 20)
    refute_nil doc.get_element_by_id("cond")
    assert_empty @h.errors, @h.error_report
  end

  # x-bind (:attr) reactively binds attributes, including :class object syntax.
  def test_x_bind
    boot(<<~HTML)
      <div x-data="{ active: true, label: 'go' }">
        <a id="lnk" :href="'/' + label" :class="{ on: active, off: !active }" x-text="label"></a>
        <button id="t" x-on:click="active = !active">t</button>
      </div>
    HTML
    lnk = doc.get_element_by_id("lnk")
    assert_equal "/go", lnk.get_attribute("href")
    assert_equal "on", lnk.get_attribute("class")
    assert_equal "go", lnk.text_content

    @h.execute("document.getElementById('t').click();")
    @h.pump(rounds: 20)
    assert_equal "off", doc.get_element_by_id("lnk").get_attribute("class")
    assert_empty @h.errors, @h.error_report
  end

  # x-for iterates a reactive array into cloned <template> content, exposing the
  # per-item variable (and index) in each clone's scope, and reconciles the list
  # as the backing array mutates. This exercises two fixes working together:
  #   * <template> content lives in an inert DocumentFragment (Dommy migrates it
  #     at page load), so Alpine's tree-walk doesn't descend into the template
  #     and evaluate `x-text="item"` out of scope; and
  #   * the host bridge recognises its own proxies by identity rather than by
  #     reading a tag symbol, so probing a Vue/Alpine `reactive()` array no longer
  #     tracks a stray symbol dep that broke length-shrinking mutations.
  def test_x_for
    boot(<<~HTML)
      <div x-data='{ "items": ["a", "b", "c"] }'>
        <ul><template x-for="(item, idx) in items" :key="item">
          <li class="row" x-text="idx + ':' + item"></li>
        </template></ul>
        <button id="push" x-on:click="items.push('d')">push</button>
        <button id="shift" x-on:click="items.shift()">shift</button>
      </div>
    HTML
    rows = -> { doc.query_selector_all("li.row").map { |li| li.text_content.strip } }
    assert_equal %w[0:a 1:b 2:c], rows.call

    @h.execute("document.getElementById('push').click();")
    @h.pump(rounds: 20)
    assert_equal %w[0:a 1:b 2:c 3:d], rows.call

    # shift() shrinks the array — the path that used to throw "cannot convert
    # symbol to number" deep in Alpine's reactivity. Indices re-render too.
    @h.execute("document.getElementById('shift').click();")
    @h.pump(rounds: 20)
    assert_equal %w[0:b 1:c 2:d], rows.call
    assert_empty @h.errors, @h.error_report
  end

  # A <template> is inert per the HTML spec: its parsed contents live in a
  # separate DocumentFragment (`.content`), not as element children. Dommy
  # migrates this at page load so frameworks that walk the DOM see an empty
  # template element with its markup available via `.content` / innerHTML.
  def test_template_content_is_inert
    boot(<<~HTML)
      <ul id="list"><template id="tpl"><li class="row">x</li></template></ul>
    HTML
    assert_equal 0, @h.evaluate("document.getElementById('tpl').childNodes.length")
    assert_nil @h.evaluate("document.getElementById('tpl').firstElementChild")
    assert_equal 1, @h.evaluate("document.getElementById('tpl').content.childNodes.length")
    assert_equal "LI", @h.evaluate("document.getElementById('tpl').content.firstElementChild.tagName")
    assert_equal "<li class=\"row\">x</li>", @h.evaluate("document.getElementById('tpl').innerHTML")
    assert_empty @h.errors, @h.error_report
  end
end
