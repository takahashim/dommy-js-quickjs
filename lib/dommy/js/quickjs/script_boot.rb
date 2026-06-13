# frozen_string_literal: true

module Dommy
  module Js
    module Quickjs
      # Boot a parsed document's classic `<script>` tags like a browser: run them
      # in document order (inline directly, external fetched through a resources
      # adapter), set `document.currentScript` around each, and replay the
      # readyState lifecycle so ready-gated startup code (Stimulus / Turbo / jQuery
      # ready) takes the real path.
      #
      #   loading -> run scripts in document order -> interactive (DOMContentLoaded)
      #           -> complete (load)
      #
      # Module / non-classic scripts are skipped (HTMLScriptElement decides). A
      # failed fetch or a throwing script is isolated; `on_error` is notified (the
      # Browser collects it for strict mode, the Capybara adapter ignores it) so
      # the rest of the page still loads. Shared by `Dommy::Browser` and the
      # Capybara driver so script boot lives in one place.
      module ScriptBoot
        module_function

        def run_document_scripts(runtime, document, resources: nil, on_error: nil)
          runtime.set_document_ready_state("loading")
          loader = install_module_loader(runtime, document, resources)
          document.scripts.each { |el| run_one(runtime, document, el, resources, loader, on_error) }
          runtime.set_document_ready_state("interactive")
          runtime.set_document_ready_state("complete")
        end

        # Wire the ESM resolver before any module runs: parse the page's first
        # <script type="importmap">, then resolve bare specifiers through it and
        # fetch module sources through `resources`. Returns the loader so inline
        # modules can be seeded under a document URL.
        def install_module_loader(runtime, document, resources)
          import_map = parse_import_map(document)
          base = document.base_uri
          base = document.url if base.to_s.empty?
          loader = ModuleLoader.new(resources, import_map, base_url: base)
          # The engine requires a Proc specifically.
          runtime.module_loader = ->(specifier, importer) { loader.call(specifier, importer) }
          loader
        end

        def parse_import_map(document)
          el = document.scripts.find { |s| s.type.to_s.strip.downcase == "importmap" }
          ImportMap.parse(el ? el.text : "")
        end

        def run_one(runtime, document, element, resources, loader, on_error)
          if (body = element.__internal_take_pending_script__)
            with_current_script(document, element) { runtime.load_script(body) }
          elsif (src = element.__internal_take_pending_src__)
            run_external(runtime, document, element, src, resources)
          elsif (mod = element.__internal_take_pending_module__)
            run_module(runtime, document, mod, loader)
          end
        rescue StandardError => e
          on_error&.call(e)
        end

        # An ES module script. `currentScript` is null for modules (spec), so it
        # is not set. An inline body is seeded under the document URL (so its
        # relative imports resolve against the page) and pinned to the page's
        # `import.meta.url`: the engine derives import.meta.url from the module's
        # unique cache key, which carries a `#dommy-inline-N` fragment for a
        # second inline module, so we set `import.meta.url` (writable) to the
        # clean page URL up front. An external module loads by its own URL.
        def run_module(runtime, document, mod, loader)
          kind, value = mod
          if kind == :inline
            base = inline_base(document)
            # No newline, so the original body's line numbers are preserved.
            body = "import.meta.url = #{base.to_json}; #{value}"
            runtime.load_module_url(loader.seed_inline(base, body))
          elsif (url = resolve_url(document, value))
            runtime.load_module_url(url)
          end
        end

        # The page URL an inline module is identified by (its import.meta.url and
        # the base for its relative imports).
        def inline_base(document)
          base = document.base_uri
          base = document.url if base.to_s.empty?
          base.to_s.empty? ? "about:blank" : base.to_s
        end

        def run_external(runtime, document, element, src, resources)
          return unless resources

          url = resolve_url(document, src)
          return unless url

          response = resources.get(url)
          return unless response&.success?

          # Cache the compiled bytecode by URL: vendored bundles re-parse on
          # every fresh VM otherwise.
          with_current_script(document, element) { runtime.load_script_cached(response.body, cache_key: url) }
        end

        # Resolve a script's `src` against the document's base URL, which is the
        # realm's own location (correct for frames too).
        def resolve_url(document, src)
          base = document.base_uri
          base = document.url if base.to_s.empty?
          ::URI.join(base.to_s, src).to_s
        rescue ::URI::InvalidURIError
          nil
        end

        def with_current_script(document, element)
          document.__internal_set_current_script__(element)
          yield
        ensure
          document.__internal_set_current_script__(nil)
        end
      end
    end
  end
end
