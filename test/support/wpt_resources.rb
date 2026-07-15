# frozen_string_literal: true

require_relative "wpt_endpoints"
module Dommy
  module Js
    # The resource layer a real WPT test page resolves its `<script src>`
    # against — so the harness boots the document's own scripts through the
    # normal browser path (ScriptBoot) instead of regex-extracting them:
    #
    #   * `/resources/testharness.js`        -> the vendored harness
    #   * `/resources/testharnessreport.js`  -> REPORT_SHIM (harvests results)
    #   * everything else                    -> the vendored WPT tree on disk,
    #                                            by URL path (so `support/x.js`
    #                                            and `/common/y.js` resolve)
    #
    # A request for a file not on disk returns nil, so a missing optional
    # include is simply skipped (the test still runs).
    module WptResources
      TESTHARNESS = ::File.expand_path("../fixtures/testharness.js", __dir__)
      WPT_ROOT    = ::File.expand_path("../fixtures/wpt", __dir__)

      # testharnessreport.js stand-in: a browser loads testharness.js then this,
      # before the test's own scripts. It silences the visual output (we harvest
      # programmatically), mirrors id'd elements onto the global for WPT's
      # "named access on the Window" (`<div id=log>` -> bare `log`), and stashes
      # each subtest's result for the Ruby side to read after completion.
      REPORT_SHIM = <<~JS
        setup({ output: false });
        globalThis.__wptResults = null;
        for (const __el of document.querySelectorAll("[id]")) {
          const __id = __el.id;
          if (__id && !(__id in globalThis)) {
            try {
              Object.defineProperty(globalThis, __id, { value: __el, configurable: true, writable: true });
            } catch (__e) {}
          }
        }
        add_completion_callback((tests) => {
          globalThis.__wptResults = tests.map((t) => ({ name: t.name, status: t.status, message: t.message }));
        });
      JS

      # testdriver.js stand-in. The real file proxies to a WebDriver automation
      # backend that synthesizes trusted user input; we map the pieces Dommy can
      # honor onto ordinary (untrusted) DOM dispatch:
      #
      #   * get_computed_role / get_computed_label — Dommy's computed role/label
      #   * click(el) — the full primary-button sequence (pointerdown, mousedown,
      #     focus, pointerup, mouseup, click). The click's activation behavior
      #     (checkbox toggle, submit, navigation) runs as part of dispatch, so a
      #     driver click behaves like a real one. Coordinates are (0,0): Dommy has
      #     no layout, so coordinate-dependent tests (which use the Actions API,
      #     left unshimmed) are out of scope.
      #
      # testdriver-vendor.js / testdriver-actions.js exist only so their
      # `<script src>` resolves; the Actions API is intentionally not shimmed.
      TESTDRIVER_SHIM = <<~JS
        globalThis.test_driver = globalThis.test_driver || {};
        test_driver.get_computed_role = (el) => Promise.resolve(el.__internal_computed_role__());
        test_driver.get_computed_label = (el) => Promise.resolve(el.__internal_computed_label__());

        test_driver.click = (el) => {
          const at = { bubbles: true, cancelable: true, composed: true, button: 0, buttons: 0, clientX: 0, clientY: 0 };
          const pt = { ...at, pointerId: 1, isPrimary: true, pointerType: "mouse" };
          try { el.dispatchEvent(new PointerEvent("pointerdown", { ...pt, buttons: 1 })); } catch (e) {}
          el.dispatchEvent(new MouseEvent("mousedown", { ...at, buttons: 1 }));
          if (typeof el.focus === "function") { try { el.focus(); } catch (e) {} }
          try { el.dispatchEvent(new PointerEvent("pointerup", pt)); } catch (e) {}
          el.dispatchEvent(new MouseEvent("mouseup", at));
          el.dispatchEvent(new MouseEvent("click", at));
          return Promise.resolve();
        };
      JS

      module_function

      def available? = ::File.exist?(TESTHARNESS) && ::File.directory?(WPT_ROOT)

      # A Resources adapter for a test loaded at `base_path` (a "/"-rooted path
      # like "/css/cssom/CSSStyleSheet.html"), so its relative includes resolve
      # against the right WPT directory.
      def build
        WptPipe.new(chain_adapters)
      end

      def chain_adapters
        ::Dommy::Resources.chain(
          ::Dommy::Resources.static(
            "/resources/testharness.js" => ::File.read(TESTHARNESS),
            "/resources/testharnessreport.js" => REPORT_SHIM,
            "/resources/testdriver.js" => TESTDRIVER_SHIM,
            "/resources/testdriver-vendor.js" => "",
            "/resources/testdriver-actions.js" => ""
          ),
          # Dynamic WPT server endpoints (resources/*.py) that fetch/xhr tests hit,
          # ahead of the static tree so an endpoint wins over any same-named file.
          WptEndpoints.new,
          ::Dommy::Resources.file_system(root: WPT_ROOT, base_url: "/")
        )
      end
    end
  end
end
