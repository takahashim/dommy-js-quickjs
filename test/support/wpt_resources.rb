# frozen_string_literal: true

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
      # backend; we only need the synchronous-ish queries WPT's accessibility
      # tests use, backed by Dommy's computed role/label on the element proxy.
      # testdriver-vendor.js / testdriver-actions.js exist only so their
      # `<script src>` resolves; they need no behavior here.
      TESTDRIVER_SHIM = <<~JS
        globalThis.test_driver = globalThis.test_driver || {};
        test_driver.get_computed_role = (el) => Promise.resolve(el.__internal_computed_role__());
        test_driver.get_computed_label = (el) => Promise.resolve(el.__internal_computed_label__());
      JS

      module_function

      def available? = ::File.exist?(TESTHARNESS) && ::File.directory?(WPT_ROOT)

      # A Resources adapter for a test loaded at `base_path` (a "/"-rooted path
      # like "/css/cssom/CSSStyleSheet.html"), so its relative includes resolve
      # against the right WPT directory.
      def build
        ::Dommy::Resources.chain(
          ::Dommy::Resources.static(
            "/resources/testharness.js" => ::File.read(TESTHARNESS),
            "/resources/testharnessreport.js" => REPORT_SHIM,
            "/resources/testdriver.js" => TESTDRIVER_SHIM,
            "/resources/testdriver-vendor.js" => "",
            "/resources/testdriver-actions.js" => ""
          ),
          ::Dommy::Resources.file_system(root: WPT_ROOT, base_url: "/")
        )
      end
    end
  end
end
