# frozen_string_literal: true

require "test_helper"

# SourceGuard works around a QuickJS bytecode-generation bug: a `for...of` whose
# iterable expression contains a `yield` fails to COMPILE ("stack underflow").
# The guard hoists the iterable into a temp `var`, and the Backend retries a
# compile/eval once when that error fires. note.com's modern bundle shipped this
# (`for (var f of (yield O(), _)) v(f)`), so the whole chunk failed to load and
# the app never mounted.
class Dommy::Js::TestSourceGuard < Minitest::Test
  SG = Dommy::Js::Quickjs::SourceGuard

  # The raw QuickJS construct fails to compile; the rewritten one must succeed.
  def test_for_of_yield_compiles_after_rewrite
    bad = "(function*(){for(var f of (yield 1, [1,2])) f})"
    assert_raises(::Quickjs::RuntimeError) { ::Quickjs::VM.new.eval_code(bad) }

    good = SG.fix_for_of_yield(bad)
    refute_equal bad, good
    refute_nil ::Quickjs::VM.new.eval_code(good), "rewritten source compiles + runs (returns the generator)"
  end

  # The Backend retries automatically, so a generator with the construct just runs.
  def test_backend_eval_recovers_via_retry
    backend = Dommy::Js::Quickjs::Backend.new
    backend.eval(<<~JS)
      globalThis.__out = [];
      function* gen() { for (var x of (yield 0, [10, 20])) __out.push(x); }
      var it = gen();
      it.next(); it.next();
    JS
    assert_equal [10, 20], backend.eval("globalThis.__out")
  end

  # Backend.compile (the cached-external-script path) also recovers.
  def test_backend_compile_recovers_via_retry
    src = "(function*(){for(var f of (yield 1, [7])) f})();"
    compiled = Dommy::Js::Quickjs::Backend.compile(src, filename: "chunk.js")
    refute_nil compiled
  end

  # Several forms of the bug all get rewritten and compile.
  def test_rewrites_common_forms
    {
      "yield-only iterable" => "(function*(){for(var f of (yield 1)) f})",
      "comma with yield"    => "(function*(){for(let x of (yield a, b)) x})",
      "destructuring decl"  => "(function*(){for(const [k,v] of (yield m, pairs)) k})",
    }.each do |label, code|
      fixed = SG.fix_for_of_yield(code)
      refute_equal code, fixed, "#{label}: should be rewritten"
      assert_includes fixed, "__dommyForOf", "#{label}: hoists into a temp var"
    end
  end

  # Safe code must NEVER be rewritten — including tokens that merely look similar.
  def test_safe_code_is_untouched
    [
      "for (var f of [1,2]) f;",                 # no yield
      "function*(){ for (var f of arr) yield f}", # yield in the BODY, not iterable
      "for (var k in obj) k;",                    # for-in
      "for (var i=0;i<n;i++) i;",                 # C-style for
      %q{var s = "for (x of (yield 1))"; s;},     # the pattern inside a string
      "for (var offset of list) offset;",         # `of`/`yield`-free identifiers
      "var re = /for.*of.*yield/g;",              # the pattern inside a regex
    ].each do |code|
      assert_equal code, SG.fix_for_of_yield(code), "must not rewrite: #{code}"
    end
  end

  # A statement-boundary check keeps the hoist correct; `yield`-free sources skip
  # the scan entirely.
  def test_sources_without_yield_are_returned_as_is
    src = "for (var f of items) use(f);"
    assert_same src, SG.fix_for_of_yield(src)
  end

  # The rewrite preserves a multibyte (UTF-8) source's encoding (note's bundle has
  # Japanese strings; the scan runs on bytes for speed).
  def test_preserves_utf8_encoding
    src = +%q{(function*(){var t="日本語";for(var f of (yield 1, [t])) f})}
    src.force_encoding("UTF-8")
    out = SG.fix_for_of_yield(src)
    assert_equal Encoding::UTF_8, out.encoding
    assert_includes out, "日本語"
  end
end
