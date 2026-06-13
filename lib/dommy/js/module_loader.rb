# frozen_string_literal: true

require "uri"

module Dommy
  module Js
    # The ESM resolver the engine consults for every `import`. Resolves a
    # specifier to an absolute URL (bare via the import map, relative against
    # the importer, absolute as-is), then fetches its source through the
    # Resources interface. CSS imports become an empty module (apps that
    # `import "./x.css"` for side effects don't crash). Returns the engine
    # contract: `{ code:, as: } | nil` (nil → module resolution error).
    class ModuleLoader
      # An empty default export so `import sheet from "./x.css"` yields an
      # object rather than failing — layout/styling is out of scope.
      CSS_STUB = "export default {};"

      def initialize(resources, import_map, base_url: nil)
        @resources = resources
        @import_map = import_map
        @base_url = base_url.to_s
        @seeded = {}
      end

      # Register an in-memory module source under `url` (served before any
      # network fetch). Used to give an inline `<script type="module">` a real
      # document-based URL as its module identity, so its relative imports
      # resolve against the page instead of a synthetic filename.
      def seed(url, source)
        @seeded[url.to_s] = source.to_s
        url.to_s
      end

      # Seed an inline module under `preferred_url` (the document URL) if free,
      # so the common single-inline-module page gets a clean
      # `import.meta.url` == the page URL. A second inline module on the same
      # page falls back to a `#dommy-inline-N` fragment for a unique module
      # identity (the engine caches modules by canonical name); the fragment is
      # ignored when resolving relative imports, so `./x` still resolves against
      # the page. Returns the chosen URL.
      def seed_inline(preferred_url, source)
        base = preferred_url.to_s
        base = "about:blank" if base.empty?
        url = base
        i = 0
        while @seeded.key?(url)
          i += 1
          url = "#{base}#dommy-inline-#{i}"
        end
        @seeded[url] = source.to_s
        url
      end

      # The engine module-loader callable.
      def call(specifier, importer = nil)
        url = resolve_url(specifier, importer)
        return nil unless url

        return {code: @seeded[url], as: url} if @seeded.key?(url)
        return {code: CSS_STUB, as: url} if css?(url)

        response = @resources&.get(url)
        return nil unless response&.success?

        {code: response.body, as: url}
      end

      # Resolve a specifier to an absolute URL string (nil if unresolvable).
      # Bare specifiers go through the import map; relative/absolute resolve
      # against the importer (or the document base URL for the entry module).
      def resolve_url(specifier, importer = nil)
        spec = specifier.to_s
        base = importer.to_s.empty? ? @base_url : importer.to_s

        if relative?(spec) || absolute?(spec) || spec.start_with?("/")
          join(base, spec)
        else
          mapped = @import_map&.resolve(spec, importer)
          mapped ? join(base, mapped) : nil
        end
      end

      private

      def relative?(spec) = spec.start_with?("./", "../")
      def absolute?(spec) = spec.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
      def css?(url) = URI.parse(url).path.to_s.downcase.end_with?(".css")

      def join(base, spec)
        return spec if absolute?(spec)
        return spec if base.to_s.empty?

        URI.join(base, spec).to_s
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
