# frozen_string_literal: true

require "test_helper"

# An assignment to a readonly [PutForwards=x] attribute is an assignment to x
# of the object it holds, so the value takes x's conversion before it reaches
# the host: `location = obj` navigates to obj's own toString, as
# `location.href = obj` does.
class Dommy::Js::TestPutForwardsConversion < Minitest::Test
  def setup
    @win = Dommy.parse('<html><body><p id="p"></p></body></html>')
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
  end

  def teardown
    @rt&.dispose
  end

  def test_an_object_assigned_to_a_location_navigates_by_its_to_string
    { "window.location" => "w", "location" => "b", "window.document.location" => "d" }.each do |target, tag|
      @rt.execute("#{target} = { toString() { return '##{tag}'; } };")
      assert_equal "http://localhost/##{tag}", @rt.evaluate("location.href"), target
    end
  end

  def test_a_symbol_assigned_to_location_is_a_type_error
    assert_raises(Quickjs::TypeError) { @rt.execute("location = Symbol('s');") }
  end

  def test_class_list_and_style_take_a_dom_string
    @rt.execute(<<~JS)
      globalThis.p = window.document.getElementById("p");
      p.classList = { toString() { return "a b"; } };
      p.style = { toString() { return "color: red"; } };
    JS
    assert_equal ["a b", "red"], @rt.evaluate("[p.className, p.style.color]")
  end
end
