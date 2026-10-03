# frozen_string_literal: true

require "test_helper"

# A module registered once per process (Runtime.register_module) and read into
# a Runtime as bytecode (Runtime.new(preload_modules:)), so a later page loads
# it without parsing its source again. The module loader reaches a preloaded
# module either by its own name or through a `{as: name}` redirect.
class Dommy::Js::TestModulePreload < Minitest::Test
  Runtime = Dommy::Js::Quickjs::Runtime

  def setup
    @names = []
    @runtimes = []
  end

  def teardown
    @runtimes.each(&:dispose)
    @names.each { |name| ::Quickjs._unregister_module(name) }
  end

  # A canonical name of this test's own, unregistered in teardown, so the
  # process-wide registry carries nothing from one test to the next.
  def register(source)
    name = "https://example.test/#{name()}/#{@names.size}.js"
    Runtime.register_module(name, source: source)
    @names << name
    name
  end

  def runtime(**opts)
    Runtime.new(**opts).tap { |rt| @runtimes << rt }
  end

  # The loader answers `{as: name}` for `specifier`, and records every
  # specifier it is asked for; anything else is not found.
  def redirect(rt, specifier, to:)
    asked = []
    rt.module_loader = lambda do |spec, _importer|
      asked << spec
      {as: to} if spec == specifier
    end
    asked
  end

  def test_a_preloaded_module_runs_when_loaded_by_its_name
    name = register("globalThis.ran = (globalThis.ran || 0) + 1; export const v = 1;")
    rt = runtime(preload_modules: [name])
    asked = redirect(rt, "unused", to: name)

    rt.load_module_url(name)

    assert_equal 1, rt.evaluate("globalThis.ran")
    assert_empty asked, "a preloaded module is found before the loader is asked for it"
  end

  def test_a_redirect_from_the_loader_reaches_the_preloaded_module
    name = register("globalThis.ran = 'preloaded';")
    rt = runtime(preload_modules: [name])
    asked = redirect(rt, "https://example.test/app.js", to: name)

    rt.load_module_url("https://example.test/app.js")

    assert_equal "preloaded", rt.evaluate("globalThis.ran")
    assert_equal ["https://example.test/app.js"], asked
  end

  def test_a_static_import_redirected_to_a_preloaded_module_gets_its_exports
    lib = register("export const answer = 42;")
    rt = runtime(preload_modules: [lib])
    rt.module_loader = lambda do |spec, _importer|
      case spec
      when "lib" then {as: lib}
      when "https://example.test/main.js" then "import { answer } from 'lib'; globalThis.got = answer;"
      end
    end

    rt.load_module_url("https://example.test/main.js")

    assert_equal 42, rt.evaluate("globalThis.got")
  end

  # Each Runtime gets an instance of its own: module-level state does not leak
  # from one page to the next, though the bytecode is shared.
  def test_each_runtime_gets_its_own_instance_of_a_preloaded_module
    name = register("let n = 0; globalThis.bump = () => ++n;")
    2.times do
      rt = runtime(preload_modules: [name])
      redirect(rt, "unused", to: name)
      rt.load_module_url(name)

      assert_equal 1, rt.evaluate("globalThis.bump()")
    end
  end

  def test_a_lazy_source_is_read_once_on_the_first_preload
    reads = 0
    name = register(-> { reads += 1; "globalThis.ran = true;" })

    assert_equal 0, reads, "registering reads nothing"
    2.times { runtime(preload_modules: [name]) }
    assert_equal 1, reads
  end

  def test_preloading_a_name_not_registered_raises
    assert_raises(ArgumentError) { runtime(preload_modules: ["https://example.test/nowhere.js"]) }
  end

  def test_without_preload_modules_a_redirect_has_nothing_to_land_on
    name = register("globalThis.ran = true;")
    rt = runtime
    redirect(rt, "https://example.test/app.js", to: name)

    assert_raises(::Quickjs::ReferenceError) { rt.load_module_url("https://example.test/app.js") }
  end
end
