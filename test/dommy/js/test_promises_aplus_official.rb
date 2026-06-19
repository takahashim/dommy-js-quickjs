# frozen_string_literal: true

require "test_helper"

# Runs the OFFICIAL promises-aplus-tests suite (vendored under
# test/support/aplus) against Dommy's host PromiseValue, inside the QuickJS
# realm, via a harness that shims the suite's Node deps and an adapter backed by
# __rbHost.makeHostDeferred. Each test is run one at a time with the scheduler
# drained between them, so the suite's setTimeout-based async assertions settle.
class Dommy::Js::TestPromisesAplusOfficial < Minitest::Test
  APLUS_DIR = File.expand_path("../../support/aplus", __dir__)

  def setup
    @win = Dommy.parse("<html></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
  end

  def teardown
    @rt&.dispose
  end

  def test_official_promises_aplus_suite
    @rt.load_script(File.read("#{APLUS_DIR}/harness.js"))

    # Helpers are `require`d by the test files — register them lazily.
    %w[reasons testThreeCases thenables].each do |helper|
      src = File.read("#{APLUS_DIR}/tests/helpers/#{helper}.js")
      @rt.load_script("__aplusRegister(#{helper.inspect}, function (require, module, exports) {\n#{src}\n});")
    end

    # Test files run top-level (registering describe/specify) — execute each.
    Dir["#{APLUS_DIR}/tests/*.js"].sort.each do |file|
      src = File.read(file)
      @rt.load_script("(function (require, module, exports) {\n#{src}\n})(__aplusRequire, { exports: {} }, {});")
    end

    count = @rt.evaluate("__aplus.collect()")
    refute_equal 0, count, "no A+ tests were collected"

    failures = []
    count.times do |i|
      @rt.execute("__aplus.start(#{i})")
      @rt.run_until_idle
      res = @rt.evaluate("__aplus.result(#{i})")
      next if res["finished"] && res["error"].nil?

      name = @rt.evaluate("__aplus.name(#{i})")
      failures << "#{name} => #{res["finished"] ? res["error"] : "TIMEOUT (done never called)"}"
    end

    puts "\nPromises/A+ official suite: #{count - failures.size}/#{count} passed"
    groups = failures.group_by do |f|
      err = f.split(" => ", 2).last
      err.start_with?("strictEqual") ? "strictEqual mismatch" : err.sub(/got.*/, "").strip
    end
    groups.sort_by { |_, v| -v.size }.each do |sig, fs|
      puts "  [#{fs.size}] #{sig}"
      puts "      e.g. #{fs.first.split(" :: ").last}"
    end
    assert_empty failures, "#{failures.size}/#{count} Promises/A+ official tests failed"
  end
end
