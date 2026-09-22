# frozen_string_literal: true

require "test_helper"

# capybara-dommy isn't published yet, so it's only on the load path inside the
# dommy monorepo. In a standalone clone, skip this file rather than aborting the
# whole suite at load time.
begin
  require "dommy/js/quickjs/capybara"
rescue LoadError
  warn "skipping test_capybara_js_errors.rb: capybara-dommy not available"
  return
end

# `Capybara::Dommy.configuration.raise_js_errors` — a JavaScript driver fails
# the example on what the page left unhandled, the way Capybara's own
# raise_server_errors fails one on a server exception.
#
# The driver itself holds no error-checking code: everything Capybara does
# reaches the session through a checkpoint already (a query pumps the clock, a
# node interaction drains, reset! disposes), so these pin down that the failure
# really does surface through the ordinary driver commands.
class Dommy::Js::TestCapybaraJsErrors < Minitest::Test
  PAGES = {
    "/clean" => "<html><body><h1>fine</h1></body></html>",
    "/boots-badly" => '<html><body><h1>hi</h1><script>throw new Error("boot failed");</script></body></html>',
    "/handles-its-own" => <<~HTML,
      <html><body><h1>hi</h1>
        <script>window.addEventListener("error", function (e) { e.preventDefault(); });</script>
        <script>throw new Error("the page handled this");</script>
      </body></html>
    HTML
    "/throws-on-a-timer" => <<~HTML,
      <html><body><h1>hi</h1><script>
        setTimeout(function () { throw new Error("from the timer"); }, 20);
      </script></body></html>
    HTML
  }.freeze

  APP = lambda do |env|
    body = PAGES[env["PATH_INFO"]]
    return [404, {"content-type" => "text/plain"}, ["nope"]] unless body

    [200, {"content-type" => "text/html"}, [body]]
  end

  def teardown
    @driver&.reset!
  rescue Dommy::JsError
    nil # a test that leaves an error pending on purpose
  ensure
    Capybara::Dommy.reset_configuration!
  end

  def driver(**options)
    @driver = Capybara::Dommy::Driver.new(APP, default_host: "http://example.org",
      javascript: true, **options)
  end

  def test_a_boot_error_fails_the_visit
    error = assert_raises(Dommy::JsError) { driver.visit("/boots-badly") }

    assert_includes error.message, "boot failed"
  end

  def test_a_page_that_handles_its_own_errors_passes
    d = driver
    d.visit("/handles-its-own")

    assert_equal 1, d.find_css("h1").length
  end

  def test_a_timer_error_surfaces_through_an_ordinary_query
    d = driver
    d.visit("/clean")
    d.execute_script('setTimeout(function () { throw new Error("from the timer"); }, 20);')

    # find_css pumps the virtual clock, which is what makes the timer come due:
    # the failure reaches the example through a plain Capybara query.
    error = assert_raises(Dommy::JsError) { 40.times { d.find_css("h1") } }
    assert_includes error.message, "from the timer"
  end

  def test_reset_fails_on_an_error_nothing_reported
    d = driver(javascript: true)
    d.visit("/clean")
    d.rack_session.__internal_js_runtime.error_log.record(RuntimeError.new("late"))

    error = assert_raises(Dommy::JsError) { d.reset! }
    assert_includes error.message, "late"
  end

  def test_allow_js_errors_lets_a_deliberate_error_through
    d = driver
    d.allow_js_errors { d.visit("/boots-badly") }

    assert(d.rack_session.js_errors.any? { |e| e.message.to_s.include?("boot failed") })
  end

  def test_the_configuration_can_turn_the_failures_off
    Capybara::Dommy.configure { |config| config.raise_js_errors = false }
    d = driver
    d.visit("/boots-badly")

    assert_equal 1, d.find_css("h1").length, "the page still loaded"
    assert(d.rack_session.js_errors.any? { |e| e.message.to_s.include?("boot failed") })
  end

  def test_a_non_javascript_driver_is_unaffected
    @driver = Capybara::Dommy::Driver.new(APP, default_host: "http://example.org")
    @driver.visit("/boots-badly")

    assert_equal 1, @driver.find_css("h1").length,
      "no JS runs, so there is nothing to fail on"
  end
end
