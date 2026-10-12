# frozen_string_literal: true

require "test_helper"

# Two window members reached by their bare names and through the window.
class Dommy::Js::TestWindowLocationAndMicrotasks < Minitest::Test
  # `location` is the window's own [PutForwards=href] attribute, so assigning
  # the bare name navigates, as assigning `window.location` does.
  def test_assigning_the_bare_location_navigates
    browser = Dommy::Browser.new(
      "<!DOCTYPE html><body><script>location = '/elsewhere'</script></body>",
      url: "http://localhost/",
    )
    assert_equal "http://localhost/elsewhere", browser.window.location.href
  ensure
    browser&.dispose
  end

  def test_the_bare_location_is_the_window_location
    browser = Dommy::Browser.new("<!DOCTYPE html><body></body>", url: "http://localhost/")
    assert_equal [true, true], browser.evaluate("[location === window.location, location === self.location]")
  ensure
    browser&.dispose
  end

  # window.queueMicrotask runs a JS callback as a microtask, and what it
  # throws is reported at the window rather than lost.
  def test_window_queue_microtask_runs_the_callback_and_reports_its_throw
    browser = Dommy::Browser.new(<<~HTML, url: "http://localhost/", strict: false)
      <!DOCTYPE html><body><script>
        globalThis.log = [];
        addEventListener("error", (e) => { log.push("reported " + e.error.message); e.preventDefault(); });
        window.queueMicrotask(() => log.push("window"));
        self.queueMicrotask(() => { throw new Error("boom"); });
        Promise.resolve().then(() => log.push("promise"));
      </script></body>
    HTML
    browser.settle
    assert_equal ["window", "reported boom", "promise"], browser.evaluate("log")
  ensure
    browser&.dispose
  end
end
