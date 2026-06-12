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
          document.scripts.each { |el| run_one(runtime, document, el, resources, on_error) }
          runtime.set_document_ready_state("interactive")
          runtime.set_document_ready_state("complete")
        end

        def run_one(runtime, document, element, resources, on_error)
          if (body = element.__internal_take_pending_script__)
            with_current_script(document, element) { runtime.load_script(body) }
          elsif (src = element.__internal_take_pending_src__)
            run_external(runtime, document, element, src, resources)
          end
        rescue StandardError => e
          on_error&.call(e)
        end

        def run_external(runtime, document, element, src, resources)
          return unless resources

          url = resolve_url(document, src)
          return unless url

          response = resources.get(url)
          return unless response&.success?

          with_current_script(document, element) { runtime.load_script(response.body) }
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
