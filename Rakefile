# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

task default: :test

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
