# frozen_string_literal: true

require "test_helper"

# Drives the *real* Vue 3 global build on Dommy + QuickJS. Vue is a useful
# counterpoint to React: a completely different architecture — Proxy-based
# reactivity (ref/reactive/computed) and a runtime template compiler — so it
# stresses the bridge along different seams. Skips unless the bundle is vendored:
#   curl -sL https://unpkg.com/vue@3/dist/vue.global.prod.js -o test/fixtures/vue.global.js
#
# Note: Vue's global build is `var Vue = …`, so it relies on a <script> running
# in global scope — which Runtime#load_script provides (unlike the IIFE-wrapping
# execute).
class Dommy::Js::TestVueIntegration < Minitest::Test
  BUNDLE = File.expand_path("../../fixtures/vue.global.js", __dir__)

  def setup
    skip "Vue bundle not vendored (#{BUNDLE})" unless File.exist?(BUNDLE)

    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head></head><body><div id='app'></div></body></html>"
    )
    @h.load_script(BUNDLE)
  end

  def teardown
    @h&.dispose
  end

  # Mount a component (an options object literal in `def_js`) and pump.
  def mount(def_js)
    @h.execute("globalThis.__app = Vue.createApp(#{def_js}); globalThis.__app.mount('#app');")
    @h.pump(rounds: 20)
  end

  def doc = @h.window.document

  def test_vue_loads
    assert_equal "object", @h.evaluate("typeof Vue")
    assert_equal "function", @h.evaluate("typeof Vue.createApp")
    assert_empty @h.errors, @h.error_report
  end

  # Reactivity + computed + an event handler: clicking increments a ref and a
  # computed derived from it re-renders.
  def test_reactivity_and_computed
    @h.execute(<<~JS)
      const { ref, computed } = Vue;
      globalThis.__C = {
        setup() {
          const n = ref(0);
          const doubled = computed(() => n.value * 2);
          return { n, doubled, inc: () => n.value++ };
        },
        template: '<div><span id="n">{{ n }}</span><span id="d">{{ doubled }}</span><button id="b" @click="inc">+</button></div>',
      };
    JS
    mount("globalThis.__C")
    assert_equal "0", doc.get_element_by_id("n").text_content
    assert_equal "0", doc.get_element_by_id("d").text_content

    @h.execute("document.getElementById('b').click();")
    @h.pump(rounds: 20)
    assert_equal "1", doc.get_element_by_id("n").text_content
    assert_equal "2", doc.get_element_by_id("d").text_content
    assert_empty @h.errors, @h.error_report
  end

  # v-model two-way binding: typing into the input updates the bound ref, which
  # re-renders the echo.
  def test_v_model
    @h.execute(<<~JS)
      const { ref } = Vue;
      globalThis.__C = {
        setup() { return { text: ref("hi") }; },
        template: '<div><input id="inp" v-model="text"><span id="echo">{{ text }}</span></div>',
      };
    JS
    mount("globalThis.__C")
    assert_equal "hi", doc.get_element_by_id("echo").text_content
    assert_equal "hi", @h.evaluate("document.getElementById('inp').value")

    @h.execute(<<~JS)
      const i = document.getElementById('inp');
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(i, 'world');
      i.dispatchEvent(new Event('input', { bubbles: true }));
    JS
    @h.pump(rounds: 20)
    assert_equal "world", doc.get_element_by_id("echo").text_content
    assert_empty @h.errors, @h.error_report
  end

  # v-for over a reactive array (with :key and :class) plus v-if, mutated by
  # events: add/remove items and toggle a conditional element.
  def test_v_for_and_v_if
    @h.execute(<<~JS)
      const { reactive, ref, computed } = Vue;
      globalThis.__C = {
        setup() {
          const items = reactive([{ id: 1, label: 'a' }]);
          const show = ref(true);
          return {
            items, show,
            count: computed(() => items.length),
            add: () => items.push({ id: items.length + 1, label: 'x' + items.length }),
            removeFirst: () => items.shift(),
          };
        },
        template: `
          <div>
            <button id="add" @click="add">add</button>
            <button id="rm" @click="removeFirst">rm</button>
            <button id="tog" @click="show = !show">toggle</button>
            <span id="cnt">{{ count }}</span>
            <ul id="list"><li v-for="i in items" :key="i.id" :class="i.label">{{ i.label }}</li></ul>
            <strong id="cond" v-if="show">shown</strong>
          </div>`,
      };
    JS
    mount("globalThis.__C")
    assert_equal '<li class="a">a</li>', doc.get_element_by_id("list").inner_html
    assert_equal "1", doc.get_element_by_id("cnt").text_content
    refute_nil doc.get_element_by_id("cond")

    @h.execute("document.getElementById('add').click();")
    @h.pump(rounds: 20)
    assert_equal '<li class="a">a</li><li class="x1">x1</li>', doc.get_element_by_id("list").inner_html
    assert_equal "2", doc.get_element_by_id("cnt").text_content

    @h.execute("document.getElementById('tog').click();")
    @h.pump(rounds: 20)
    assert_nil doc.get_element_by_id("cond")

    @h.execute("document.getElementById('rm').click();")
    @h.pump(rounds: 20)
    assert_equal "1", doc.get_element_by_id("cnt").text_content
    assert_empty @h.errors, @h.error_report
  end

  # watch + watchEffect react to a ref change; lifecycle hooks fire on
  # mount/unmount.
  def test_watchers_and_lifecycle
    @h.execute(<<~JS)
      const { ref, watch, watchEffect, onMounted, onUnmounted } = Vue;
      globalThis.__log = [];
      const Child = {
        setup() {
          const n = ref(0);
          watch(n, (v, o) => globalThis.__log.push("watch:" + o + "->" + v));
          watchEffect(() => globalThis.__log.push("effect:" + n.value));
          onMounted(() => globalThis.__log.push("mounted"));
          onUnmounted(() => globalThis.__log.push("unmounted"));
          globalThis.__bump = () => n.value++;
          return { n };
        },
        template: '<span id="n">{{ n }}</span>',
      };
      globalThis.__C = {
        components: { Child },
        setup() { const show = ref(true); globalThis.__hide = () => { show.value = false; }; return { show }; },
        template: '<Child v-if="show" />',
      };
    JS
    mount("globalThis.__C")
    assert_equal ["effect:0", "mounted"], @h.evaluate("globalThis.__log")

    @h.execute("globalThis.__bump();")
    @h.pump(rounds: 20)
    assert_equal ["effect:0", "mounted", "watch:0->1", "effect:1"], @h.evaluate("globalThis.__log")

    @h.execute("globalThis.__hide();")
    @h.pump(rounds: 20)
    assert_includes @h.evaluate("globalThis.__log"), "unmounted"
    assert_empty @h.errors, @h.error_report
  end

  # provide/inject passes a value down through component layers.
  def test_provide_inject
    @h.execute(<<~JS)
      const { provide, inject } = Vue;
      const Child = { setup() { return { msg: inject("msg") }; }, template: '<span id="ij">{{ msg }}</span>' };
      globalThis.__C = { components: { Child }, setup() { provide("msg", "injected"); }, template: '<Child />' };
    JS
    mount("globalThis.__C")
    assert_equal "injected", doc.get_element_by_id("ij").text_content
    assert_empty @h.errors, @h.error_report
  end

  # Named and scoped slots: a parent fills a named slot and consumes a slot prop.
  def test_named_and_scoped_slots
    @h.execute(<<~JS)
      const Box = { template: '<div><header id="h"><slot name="head"/></header><main id="m"><slot :x="42"/></main></div>' };
      globalThis.__C = { components: { Box }, template: '<Box><template #head>HEAD</template><template #default="sp">val={{ sp.x }}</template></Box>' };
    JS
    mount("globalThis.__C")
    assert_equal "HEAD", doc.get_element_by_id("h").text_content
    assert_equal "val=42", doc.get_element_by_id("m").text_content
    assert_empty @h.errors, @h.error_report
  end

  # Directive/binding sugar: v-show toggles display, :class object syntax and
  # :style object syntax render, and event modifiers (.stop/.prevent) apply.
  def test_directives_and_bindings
    @h.execute(<<~JS)
      const { ref } = Vue;
      globalThis.__C = {
        setup() {
          const on = ref(true);
          globalThis.__order = [];
          return {
            on,
            toggle: () => { on.value = !on.value; },
            outer: () => globalThis.__order.push("outer"),
            inner: (e) => globalThis.__order.push("inner:" + e.defaultPrevented),
          };
        },
        template: `
          <div @click="outer">
            <span id="box" v-show="on" :class="{ active: on, off: !on }" :style="{ color: 'red' }">x</span>
            <button id="t" @click="toggle">t</button>
            <a id="lnk" href="#" @click.stop.prevent="inner">go</a>
          </div>`,
      };
    JS
    mount("globalThis.__C")
    box = doc.get_element_by_id("box")
    assert_equal "active", box.get_attribute("class")
    assert_equal "color: red;", box.get_attribute("style")
    assert_equal "", @h.evaluate("document.getElementById('box').style.display")

    # v-show toggles the inline display style off when the condition is false.
    @h.execute("document.getElementById('t').click();")
    @h.pump(rounds: 20)
    assert_equal "none", @h.evaluate("document.getElementById('box').style.display")
    assert_equal "off", doc.get_element_by_id("box").get_attribute("class")

    @h.execute("globalThis.__order = []; document.getElementById('lnk').click();")
    @h.pump(rounds: 20)
    # .stop kept the click from reaching the outer handler; .prevent set defaultPrevented.
    assert_equal ["inner:true"], @h.evaluate("globalThis.__order")
    assert_empty @h.errors, @h.error_report
  end

  # Teleport renders its children into a different container.
  def test_teleport
    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head></head><body><div id='app'></div><div id='tp'></div></body></html>"
    )
    @h.load_script(BUNDLE)
    @h.execute(%q{globalThis.__C = { template: '<div>main<Teleport to="#tp"><span id="tel">TELEPORTED</span></Teleport></div>' };})
    mount("globalThis.__C")
    assert_equal '<span id="tel">TELEPORTED</span>', doc.get_element_by_id("tp").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # Dynamic components (<component :is>) and an async component resolved through
  # Suspense both render.
  def test_dynamic_and_async_components
    @h.execute(<<~JS)
      const { ref, defineAsyncComponent } = Vue;
      const A = { template: '<span id="dc">AAA</span>' };
      const B = { template: '<span id="dc">BBB</span>' };
      globalThis.__C = {
        components: {
          A, B,
          Async: defineAsyncComponent(() => Promise.resolve({ template: '<span id="ac">ASYNC</span>' })),
        },
        setup() { const cur = ref("A"); globalThis.__swap = () => { cur.value = "B"; }; return { cur }; },
        template: '<div><component :is="cur" /><Suspense><Async /><template #fallback>…</template></Suspense></div>',
      };
    JS
    mount("globalThis.__C")
    @h.pump(rounds: 40)
    assert_equal "AAA", doc.get_element_by_id("dc").text_content
    assert_equal "ASYNC", doc.get_element_by_id("ac").text_content

    @h.execute("globalThis.__swap();")
    @h.pump(rounds: 20)
    assert_equal "BBB", doc.get_element_by_id("dc").text_content
    assert_empty @h.errors, @h.error_report
  end

  # Component composition: a parent passes a prop to a registered child component
  # and listens for the child's emitted event.
  def test_components_props_and_emit
    @h.execute(<<~JS)
      const { ref } = Vue;
      globalThis.__C = {
        components: {
          Child: {
            props: ['label'],
            emits: ['ping'],
            template: '<button class="child" @click="$emit(\\'ping\\')">{{ label }}</button>',
          },
        },
        setup() { const pings = ref(0); return { pings, onPing: () => pings.value++ }; },
        template: '<div><Child label="hi" @ping="onPing" /><span id="pings">{{ pings }}</span></div>',
      };
    JS
    mount("globalThis.__C")
    assert_equal "hi", doc.query_selector(".child").text_content
    assert_equal "0", doc.get_element_by_id("pings").text_content

    @h.execute("document.querySelector('.child').click();")
    @h.pump(rounds: 20)
    assert_equal "1", doc.get_element_by_id("pings").text_content
    assert_empty @h.errors, @h.error_report
  end
end
