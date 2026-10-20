# frozen_string_literal: true

require "test_helper"

# The shims (js/*.js) run as classic scripts in the page's realm, so a helper
# declared at their top level would be a global binding: a page's own
# top-level `let` of the same name a redeclaration SyntaxError, and a page's
# binding of a name a shim looks up globally a hijack of the shim.
class Dommy::Js::TestShimScope < Minitest::Test
  HELPERS = %w[
    I group NumberFormat DateTimeFormat Collator PluralRules RelativeTimeFormat ListFormat
    unsupported throwUnsupported
    __rbDefer __rbTimerOrigins __rbTimerForward __rbTimerMember
    __rbForward __rbMember __rbLocationWindow __rbLocation __rbWindowOperation __rbForwardWindowMethod
  ].freeze

  def setup
    @win = Dommy.parse("<!DOCTYPE html><html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
  end

  def teardown
    @rt&.dispose
  end

  def test_shim_helpers_are_not_globals
    HELPERS.each do |name|
      assert_equal "undefined", @rt.evaluate("typeof #{name}"), name
    end
  end

  def test_a_page_can_declare_a_shim_helper_name
    HELPERS.each do |name|
      @rt.load_script("let #{name} = 5;")
      assert_equal 5, @rt.evaluate(name), name
    end
  end

  # The timers reach their origin map through a local, so a page binding with
  # the name it once had can't break scheduling.
  def test_a_page_binding_does_not_break_the_timers
    @rt.load_script("let __rbTimerOrigins = 1;")
    @rt.load_script("setTimeout(() => { window.FIRED = true; }, 0);")
    @rt.run_until_idle
    assert_equal true, @rt.evaluate("window.FIRED")
  end

  def test_the_shims_still_install_from_their_iife
    assert_equal "1,234.5", @rt.evaluate('new Intl.NumberFormat("en").format(1234.5)')
    assert_equal false, @rt.evaluate("WebAssembly.validate(new Uint8Array([0]))")
    assert_equal "function", @rt.evaluate("typeof fetch")
    assert_equal true, @rt.evaluate("location === window.location")
  end
end
