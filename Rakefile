# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

# The OOM-resilience test forces a real QuickJS out-of-memory. Whether an OOM
# poisons the VM (vs. unwinding as a recoverable JS exception) depends on the
# allocator's state, which other JS-heavy tests in the same process perturb — so
# it runs in its own process to stay deterministic.
OOM_TEST = "test/dommy/js/test_oom_resilience.rb"

Minitest::TestTask.create(:test) do |t|
  t.test_globs = FileList["test/**/test_*.rb"].exclude(OOM_TEST)
end

Minitest::TestTask.create(:test_oom) do |t|
  t.test_globs = [OOM_TEST]
end

namespace :test do
  desc "Run the full test suite including the heavy (thousands-of-subtests) WPT files"
  task :all do
    ENV["WPT_HEAVY"] = "1"
    Rake::Task["test"].invoke
    Rake::Task["test_oom"].invoke
  end
end

task default: %i[test test_oom]

namespace :wpt do
  desc "Run the vendored WPT corpus against the bridge and report a conformance rate"
  task :conformance, [:filter] do |_t, args|
    $LOAD_PATH.unshift File.expand_path("test", __dir__)
    require "test_helper"
    require "support/wpt_runner"

    runner = Dommy::Js::WptRunner
    files = runner.manifest
    files = files.grep(/#{args[:filter]}/) if args[:filter]

    total_pass = total = file_ok = 0
    blocked = []
    by_dir = Hash.new { |h, k| h[k] = [0, 0] } # dir => [pass, total]
    files.each do |rel|
      results = runner.run(rel)
      pass = results.count(&:pass?)
      n = results.size
      total_pass += pass
      total += n
      dir = rel.split("/").first
      by_dir[dir][0] += pass
      by_dir[dir][1] += n
      file_ok += 1 if n.positive? && pass == n
      flag = n.zero? ? "—" : (pass == n ? "✓" : " ")
      printf("  %s %-46s %3d/%-3d\n", flag, rel, pass, n)
      results.reject(&:pass?).first(3).each { |r| puts "        #{r.to_s[0, 110]}" }
    rescue => e
      blocked << rel
      puts "  ✗ #{rel}  (errored: #{e.class}: #{e.message[0, 80]})"
    end

    pct = ->(p, t) { t.zero? ? 0 : (100.0 * p / t).round(1) }
    puts
    by_dir.sort.each { |dir, (p, t)| printf("  %-8s %4d/%-5d (%.1f%%)\n", dir, p, t, pct.call(p, t)) }
    puts
    puts "WPT conformance: #{total_pass}/#{total} subtests (#{pct.call(total_pass, total)}%) across #{files.size} files; " \
         "#{file_ok} files fully green#{blocked.empty? ? "" : ", #{blocked.size} errored"}"
  end
end

namespace :stimulus do
  desc "Run @hotwired/stimulus's QUnit suite against the bridge and report a conformance rate"
  task :conformance, [:filter] do |_t, args|
    $LOAD_PATH.unshift File.expand_path("test", __dir__)
    require "test_helper"
    require "support/stimulus_conformance"

    runner = Dommy::Js::StimulusConformance
    unless runner.available?
      abort "Stimulus suite not vendored. Build it: script/build_stimulus_tests.sh"
    end

    manifest = runner.manifest
    manifest = manifest.select { |t| t["module"].match?(/#{args[:filter]}/i) } if args[:filter]

    # Run each test in its own VM, grouping the printed output by module.
    by_module = Hash.new { |h, k| h[k] = [] }
    failures = []
    manifest.each do |t|
      r = runner.run_test(t["module"], t["name"])
      by_module[t["module"]] << r
    rescue => e
      puts "  ✗ #{t["module"]} :: #{t["name"]}  (errored: #{e.class}: #{e.message[0, 70]})"
    end

    total_pass = total_runnable = total = 0
    by_module.each do |mod, results|
      pass = results.count(&:pass?)
      runnable = results.count(&:runnable?)
      total_pass += pass
      total_runnable += runnable
      total += results.size
      flag = runnable.positive? && pass == runnable ? "✓" : " "
      printf("  %s %-42s %3d/%-3d\n", flag, mod, pass, runnable)
      results.reject { |r| r.pass? || r.skip? || r.todo? }.each do |r|
        failures << r
        puts "        #{r.to_s[0, 120]}"
      end
    end

    pct = total_runnable.zero? ? 0 : (100.0 * total_pass / total_runnable).round(1)
    puts
    puts "Stimulus conformance: #{total_pass}/#{total_runnable} runnable tests (#{pct}%) " \
         "across #{by_module.size} modules; #{total - total_runnable} skipped/todo, #{failures.size} failing"
  end
end
