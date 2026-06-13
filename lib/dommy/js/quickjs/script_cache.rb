# frozen_string_literal: true

module Dommy
  module Js
    module Quickjs
      # A process-global cache of compiled external-script bytecode, keyed by
      # URL. Vendored bundles (turbo.umd.js, stimulus.umd.js, application.js, …)
      # are identical across page loads but otherwise re-parsed on every fresh
      # VM; compiling each once and running the bytecode per VM removes that
      # repeated parse cost (the bundles are hundreds of KB).
      #
      # Keyed by URL: an asset URL maps 1:1 to its content (Propshaft / Sprockets
      # digest-stamp it; test fixtures are stable within a process).
      module ScriptCache
        @cache = {}
        @mutex = Mutex.new

        class << self
          # The compiled bytecode for `url`, compiling `source` on first use.
          def compiled(url, source)
            @mutex.synchronize { @cache[url] ||= Backend.compile(source, filename: url.to_s) }
          end

          def clear
            @mutex.synchronize { @cache.clear }
          end

          def size = @cache.size
        end
      end
    end
  end
end
