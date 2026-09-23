# frozen_string_literal: true

require "test_helper"

# Location is the one interface a page must not be able to lie about: if it
# could plant its own `href`, or reparent the object, or seal it, it could make
# code that checks where it is read the wrong answer. So every member is
# [LegacyUnforgeable] — an own, non-configurable property of the instance — and
# the object's shape is fixed too.
#
# These live here rather than in core because host_runtime.js is only executed
# by a real engine, and that is what runs the proxy traps under test.
class Dommy::Js::TestLocationExotic < Minitest::Test
  def setup
    @h = Dommy::Js::BrowserHarness.new
  end

  def teardown
    @h&.dispose
  end

  def js(source) = @h.evaluate("(() => { #{source} })()")

  def test_members_are_own_properties
    assert(js("return Object.hasOwn(location, 'href');"))
    assert(js("return Object.hasOwn(location, 'toString');"))
    assert(js("return Object.hasOwn(location, 'assign');"))
  end

  def test_stringifier_is_enumerable_and_fixed
    descriptor = js("const d = Object.getOwnPropertyDescriptor(location, 'toString');
                     return [d.enumerable, d.writable, d.configurable].join(',');")

    assert_equal "true,false,false", descriptor
  end

  def test_attribute_is_an_enumerable_non_configurable_accessor
    descriptor = js("const d = Object.getOwnPropertyDescriptor(location, 'href');
                     return [d.enumerable, d.configurable, typeof d.get, typeof d.set].join(',');")

    assert_equal "true,false,function,function", descriptor
  end

  def test_readonly_attribute_has_no_setter
    assert_equal "undefined", js("return typeof Object.getOwnPropertyDescriptor(location, 'origin').set;")
  end

  def test_redefining_a_member_throws
    assert(js(<<~JS))
      try { Object.defineProperty(location, 'toString', { get() {}, configurable: true }); return false; }
      catch (e) { return e instanceof TypeError; }
    JS
  end

  # The stringifier is reachable as a bare function, so it has to check what it
  # was called on.
  def test_stringifier_rejects_a_foreign_receiver
    assert_equal "true,true,true,true", js(<<~JS)
      return [null, undefined, {}, globalThis].map(v => {
        try { location.toString.call(v); return false; } catch (e) { return e instanceof TypeError; }
      }).join(',');
    JS
  end

  def test_stringifier_answers_the_href
    assert_equal js("return location.href;"), js("return String(location);")
  end

  def test_valueof_and_to_primitive_are_pinned
    assert(js("return location.valueOf === Object.prototype.valueOf;"))
    assert_equal "false,false,false", js("const d = Object.getOwnPropertyDescriptor(location, 'valueOf');
                                          return [d.enumerable, d.writable, d.configurable].join(',');")
    assert(js("return location[Symbol.toPrimitive] === undefined;"))
    assert_equal "false,false,false", js("const d = Object.getOwnPropertyDescriptor(location, Symbol.toPrimitive);
                                          return [d.enumerable, d.writable, d.configurable].join(',');")
  end

  def test_cannot_be_sealed
    refute(js("return Reflect.preventExtensions(location);"))
    assert(js("try { Object.preventExtensions(location); return false; } catch (e) { return e instanceof TypeError; }"))
  end

  # SetImmutablePrototype: setting it to what it already is asks for nothing and
  # succeeds; anything else fails.
  def test_prototype_is_immutable
    refute(js("return Reflect.setPrototypeOf(location, {});"))
    assert(js("try { Object.setPrototypeOf(location, {}); return false; } catch (e) { return e instanceof TypeError; }"))
    assert(js("try { location.__proto__ = {}; return false; } catch (e) { return e instanceof TypeError; }"))
    assert(js("return Reflect.setPrototypeOf(location, Location.prototype);"))
    assert(js("return Object.getPrototypeOf(location) === Location.prototype;"))
  end

  def test_setters_still_reach_the_host
    assert_equal "#here", js("location.hash = 'here'; return location.hash;")
  end

  # document.location is [LegacyUnforgeable] too, and its accessor pair is
  # shared, so two Documents hand back the same getter and setter.
  def test_document_location_accessors_are_shared
    assert(js(<<~JS))
      const a = Object.getOwnPropertyDescriptor(new Document(), 'location');
      const b = Object.getOwnPropertyDescriptor(new Document(), 'location');
      return a.get === b.get && a.set === b.set && typeof a.get === 'function';
    JS
  end

  # A page can hold on to a removed frame's location. What it holds is inert.
  def test_location_without_a_browsing_context_is_inert
    assert_equal "about:blank,null,0", js(<<~JS)
      const frame = document.body.appendChild(document.createElement('iframe'));
      const loc = frame.contentWindow.location;
      frame.remove();
      loc.href = 'https://example.com/';
      loc.hash = 'x';
      loc.assign('https://example.com/');
      loc.replace('https://example.com/');
      return [loc.href, loc.origin, loc.ancestorOrigins.length].join(',');
    JS
  end
end
