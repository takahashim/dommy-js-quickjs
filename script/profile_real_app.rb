# frozen_string_literal: true

# Real-app bridge profile (roadmap D4b): drive the heaviest DOM consumers we
# ship fixtures for — a React list render/re-render and a Turbo 8 morph — and
# report wall time plus the top bridge crossings per phase, so bridge work
# (B4: JS-side reflection writes, batch reads) is prioritized from data.
#
#   DOMMY_JS_BRIDGE_PROFILE=1 bundle exec ruby script/profile_real_app.rb
#   ROWS=500 DOMMY_JS_BRIDGE_PROFILE=1 bundle exec ruby script/profile_real_app.rb

ENV["DOMMY_JS_BRIDGE_PROFILE"] ||= "1"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dommy/js/quickjs"
require "dommy"
require_relative "../test/support/browser_harness"

ROWS = Integer(ENV.fetch("ROWS", 300))
TOP = Integer(ENV.fetch("TOP", 15))

FIXTURES = File.expand_path("../test/fixtures", __dir__)
REACT = File.join(FIXTURES, "react.umd.js")
REACT_DOM = File.join(FIXTURES, "react-dom.umd.js")
TURBO = File.join(FIXTURES, "turbo.umd.js")

def phase(harness, label)
  runtime = harness.runtime
  runtime.reset_bridge_crossing_counts
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  # crossing_counts is {category => {member => count}} where each category ALSO
  # carries a "__total__" pseudo-member equal to that category's real crossing
  # count. So the true total is the sum of the __total__ values, and the
  # per-member ranking must EXCLUDE __total__ (summing everything double-counts
  # every member-bearing crossing).
  raw = runtime.bridge_crossing_counts
  total = raw.sum { |_category, members| members["__total__"] || members.values.sum }
  counts = raw.flat_map do |category, members|
    members.reject { |member, _| member == "__total__" }
           .map { |member, n| ["#{category} #{member}", n] }
  end
  puts format("\n== %-42s %8.1f ms  %6d crossings (%.1f us/crossing)",
    label, elapsed * 1000, total, total.zero? ? 0 : elapsed * 1_000_000 / total)
  counts.sort_by { |_, n| -n }.first(TOP).each do |name, n|
    puts format("   %-52s %6d", name, n)
  end
  raise "JS errors in #{label}: #{harness.error_report}" unless harness.errors.empty?
end

puts "ROWS=#{ROWS} backend=#{Dommy::Backend.current.name.split('::').last} profile=#{ENV['DOMMY_JS_BRIDGE_PROFILE']}"

# ---------------- React: list render + state-driven re-render ----------------
if File.exist?(REACT) && File.exist?(REACT_DOM)
  h = Dommy::Js::BrowserHarness.new(
    "<!DOCTYPE html><html><head></head><body><div id='root'></div></body></html>"
  )
  h.load_script(REACT)
  h.load_script(REACT_DOM)
  h.execute(<<~JS)
    const e = React.createElement;
    const Row = ({item}) =>
      e("li", {className: "row " + (item.done ? "done" : "todo"), "data-id": item.id},
        e("span", {className: "title"}, item.title),
        e("button", {className: "toggle"}, item.done ? "undo" : "do"));
    globalThis.App = ({items}) =>
      e("ul", {id: "list"}, items.map(item => e(Row, {key: item.id, item})));
    globalThis.__items = Array.from({length: #{ROWS}}, (_, i) =>
      ({id: i, title: "item " + i, done: false}));
    globalThis.__root = ReactDOM.createRoot(document.getElementById("root"));
  JS

  phase(h, "React: initial render (#{ROWS} rows)") do
    h.execute("__root.render(React.createElement(App, {items: __items}));")
    h.pump(rounds: 30)
  end

  phase(h, "React: re-render (all #{ROWS} rows changed)") do
    h.execute(<<~JS)
      __items = __items.map(it => ({...it, title: it.title + "*", done: !it.done}));
      __root.render(React.createElement(App, {items: __items}));
    JS
    h.pump(rounds: 30)
  end
  h.dispose
else
  puts "-- React bundles not vendored, skipping"
end

# ---------------- Turbo 8 morph: every row's text changes ----------------
if File.exist?(TURBO)
  rows = (1..ROWS).map { |i| "<li id='row#{i}' class='row' data-id='#{i}'>item #{i}</li>" }.join
  morphed = (1..ROWS).map { |i| "<li id='row#{i}' class='row done' data-id='#{i}'>item #{i}*</li>" }.join
  page = "<!DOCTYPE html><html><head><meta name=\"turbo-refresh-method\" content=\"morph\"></head>" \
         "<body><ul id='list'>%s</ul></body></html>"

  h = Dommy::Js::BrowserHarness.new(format(page, rows))
  h.stub_fetch("http://localhost/" => {
    "status" => 200, "contentType" => "text/html", "body" => format(page, morphed)
  })
  h.load_script(TURBO)
  h.pump(rounds: 10)

  phase(h, "Turbo: morph refresh (#{ROWS} rows changed)") do
    h.execute('Turbo.renderStreamMessage(\'<turbo-stream action="refresh"></turbo-stream>\');')
    h.pump(rounds: 60)
  end
  raise "morph did not land" unless h.evaluate("document.getElementById('row1').textContent") == "item 1*"
  h.dispose
else
  puts "-- Turbo bundle not vendored, skipping"
end
