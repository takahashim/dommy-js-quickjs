# frozen_string_literal: true

# Micro-benchmark for the Ruby<->JS bridge hot paths (roadmap 戦線D / D4a).
#
#   bundle exec ruby script/bench_bridge.rb          # N=2000 (default)
#   N=5000 bundle exec ruby script/bench_bridge.rb
#
# Reports us/op for the crossings frameworks hit hardest, plus the pure-Ruby
# equivalents (no bridge) as a floor, and one-time VM boot cost. Use it to show
# before/after numbers for any bridge/DOM perf change (e.g. the selector-AST
# cache, D1a). It is deliberately dependency-free: Ruby 4 dropped `benchmark`
# from the bundled gems, so timing is a thin Process.clock_gettime wrapper.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dommy/js/quickjs"
require "dommy"
require_relative "../test/support/browser_harness"

Dommy::Backend.use(ENV["DOMMY_BACKEND"].to_sym) if ENV["DOMMY_BACKEND"]

N = Integer(ENV.fetch("N", 2000))

def realtime
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
end

def bench(label)
  # One warm-up pass, then take the best of three to damp GC/JIT noise.
  yield
  best = 3.times.map { realtime { yield } }.min
  puts format("%-48s %8.2f ms  (%7.2f us/op)", label, best * 1000, best * 1_000_000 / N)
end

h = Dommy::Js::BrowserHarness.new(<<~HTML)
  <!DOCTYPE html><html><head></head><body>
  <div id="root" class="a b c" data-x="1"><span>hi</span></div>
  </body></html>
HTML

puts "N=#{N}  backend=#{Dommy::Backend.current.name.split('::').last}"
puts "--- JS -> Ruby crossings (what frameworks pay) ---"

h.evaluate("globalThis.__obj = {x: 1}; globalThis.__el = document.getElementById('root'); 0")

bench("JS: plain object property read (floor)") do
  h.evaluate("var s=0; for (var i=0;i<#{N};i++) s += __obj.x; s")
end
bench("JS->Ruby: getAttribute('data-x')") do
  h.evaluate("var s=0; for (var i=0;i<#{N};i++) s += __el.getAttribute('data-x').length; s")
end
bench("JS->Ruby: el.id read") do
  h.evaluate("var s=0; for (var i=0;i<#{N};i++) s += __el.id.length; s")
end
# textContent + traversal props are cached per-DOM-epoch (D2b), so a walk's
# repeated reads cross once, not once per iteration.
bench("JS->Ruby: textContent read") do
  h.evaluate("var s=0; for (var i=0;i<#{N};i++) s += __el.textContent.length; s")
end
bench("JS->Ruby: parentNode read") do
  h.evaluate("for (var i=0;i<#{N};i++) __el.parentNode; 0")
end
bench("JS->Ruby: nextSibling read") do
  h.evaluate("for (var i=0;i<#{N};i++) __el.nextSibling; 0")
end
bench("JS->Ruby: setAttribute('data-x', i)") do
  h.evaluate("for (var i=0;i<#{N};i++) __el.setAttribute('data-x', ''+i); 0")
end
bench("JS->Ruby: querySelector('#root span')") do
  h.evaluate("for (var i=0;i<#{N};i++) document.querySelector('#root span'); 0")
end
bench("JS->Ruby: create+append+remove") do
  h.evaluate("for (var i=0;i<#{N};i++){var d=document.createElement('div');__el.appendChild(d);d.remove();} 0")
end

puts "--- Ruby-direct equivalents (no bridge, floor) ---"
doc = h.window.document
el = doc.get_element_by_id("root")
bench("Ruby: getAttribute") { N.times { el.get_attribute("data-x") } }
bench("Ruby: setAttribute") { N.times { |i| el.set_attribute("data-x", i.to_s) } }
bench("Ruby: querySelector") { N.times { doc.query_selector("#root span") } }
bench("Ruby: matches?") { N.times { el.matches?("#root.a[data-x]") } }
bench("Ruby: create+append+remove") do
  N.times do
    d = doc.create_element("div")
    el.append_child(d)
    d.remove
  end
end

# A mutation-then-query loop: this is where the selector-AST cache (D1a) shows,
# because each style_generation bump invalidates the query-result cache and the
# selector string is otherwise re-parsed on the next query.
bench("Ruby: mutate+querySelector (AST cache path)") do
  N.times do |i|
    el.set_attribute("data-n", i.to_s) # bumps style_generation -> query cache miss
    doc.query_selector("#root .a[data-x]")
  end
end

# Bulk DOM construction into a DETACHED subtree, then a single attach — the SPA
# hydration / fragment-building pattern. This is where MutationCoordinator gating
# (D1c) shows: each detached append skips the O(subtree) connected/disconnected
# lifecycle walk (nothing connected can fire) and, with no observers, the record
# allocation. Attaching once still fires lifecycle for the whole subtree.
bench("Ruby: detached bulk build + attach (mutation gating)") do
  detached = doc.create_element("div")
  N.times do
    node = doc.create_element("div")
    node.set_attribute("class", "x")
    node.append_child(doc.create_text_node("t"))
    detached.append_child(node)
  end
  el.append_child(detached)
  el.remove_child(detached)
end

puts "--- VM lifecycle ---"
t = realtime { 5.times { Dommy::Js::BrowserHarness.new.dispose } }
puts format("%-48s %8.2f ms each", "VM boot: BrowserHarness.new + dispose", t * 1000 / 5)

h.dispose
