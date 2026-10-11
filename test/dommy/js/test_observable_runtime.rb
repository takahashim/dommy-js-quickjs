# frozen_string_literal: true

require "test_helper"

# Two properties of observable_runtime.js that the WPT files do not pin: the
# WebIDL conversion of take()/drop()'s count, and the absence of the internal
# operations from the interfaces' public shape.
class Dommy::Js::TestObservableRuntime < Minitest::Test
  def setup
    @win = Dommy.parse("<html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
    @rt.define_host_object("document", @win.document)
  end

  def teardown
    @rt&.dispose
  end

  # `unsigned long long` answers +0 for NaN and for either infinity, so those
  # counts take nothing; a negative one wraps to a count no source reaches.
  def test_take_converts_its_count_like_webidl
    assert_equal([[], [], [1, 2, 3], [1]], @rt.evaluate(<<~JS))
      (() => {
        const source = new Observable((s) => { s.next(1); s.next(2); s.next(3); s.complete(); });
        const taken = (n) => { const out = []; source.take(n).subscribe((v) => out.push(v)); return out; };
        return [taken(NaN), taken(Infinity), taken(-1), taken(1)];
      })()
    JS
  end

  # drop() reads the same conversion: dropping NaN drops nothing.
  def test_drop_converts_its_count_like_webidl
    assert_equal([[1, 2, 3], [1, 2, 3], [], [2, 3]], @rt.evaluate(<<~JS))
      (() => {
        const source = new Observable((s) => { s.next(1); s.next(2); s.next(3); s.complete(); });
        const dropped = (n) => { const out = []; source.drop(n).subscribe((v) => out.push(v)); return out; };
        return [dropped(NaN), dropped(Infinity), dropped(-1), dropped(1)];
      })()
    JS
  end

  # The operations operators use on their source and on their subscriber are not
  # part of the interface, so they must not appear on its shape — a page that
  # enumerates the prototype (idlharness does) must see only what the IDL
  # declares, and must not be able to replace them.
  def test_the_internal_operations_are_not_on_the_public_shape
    assert_equal([[], [], true], @rt.evaluate(<<~JS))
      (() => {
        const names = (o) => Object.getOwnPropertyNames(o).filter((n) => n.startsWith("_"));
        const source = new Observable((s) => { s.next(1); s.complete(); });
        let taken = [];
        source.map((v) => v * 2).subscribe((v) => taken.push(v));
        return [names(Observable.prototype), names(Subscriber.prototype), taken.length === 1];
      })()
    JS
  end

  # Closing a sync iterator on abort runs inside abort(), so what return()
  # throws comes out of the abort() that a promise-returning operator's
  # signal took, and out of a Subscriber's complete() — but only after the
  # observers have heard the completion. When take(1) completes inside the
  # source's loop it ends up reported, after the completion (as in Chrome).
  def test_closing_a_sync_iterator_throws_to_what_closed_it
    @rt.evaluate(<<~JS)
      globalThis.log = [];
      addEventListener("error", (e) => log.push("reported " + e.error.message));
      globalThis.closing = (name, onNext) => ({
        [Symbol.iterator]() {
          let i = 0;
          return {
            next: () => { i++; if (onNext) onNext(i); return { value: i, done: false }; },
            return: () => { throw new Error(name); },
          };
        },
      });
      const caught = (fn) => { try { fn(); log.push("returned"); } catch (e) { log.push("threw " + e.message); } };

      const controller = new AbortController();
      Observable.from(closing("toArray", (i) => { if (i === 3) caught(() => controller.abort("why")); }))
        .toArray({ signal: controller.signal })
        .catch((reason) => log.push("rejected " + reason));

      new Observable((subscriber) => {
        Observable.from(closing("complete")).subscribe({ next() { caught(() => subscriber.complete()); } }, { signal: subscriber.signal });
      }).subscribe({ complete: () => log.push("completed") });

      Observable.from(closing("take")).take(1).subscribe({ complete: () => log.push("take completed") });
    JS
    assert_equal(
      ["threw toArray", "completed", "threw complete", "take completed", "reported take", "rejected why"],
      @rt.evaluate("log"),
    )
  end
end
