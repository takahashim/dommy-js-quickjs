# frozen_string_literal: true

require "json"
require "uri"

module Dommy
  module Js
    module Quickjs
      # A parsed `<script type="importmap">`: resolves bare specifiers to URLs
      # per the import-maps proposal (the subset Rails' importmap-rails and most
      # apps use — `imports` with exact and trailing-slash-prefix matches, plus
      # basic `scopes`). Relative/absolute specifiers are not the import map's
      # job; the ModuleLoader resolves those against the importer.
      class ImportMap
        # Build from the importmap JSON text (a `<script type=importmap>` body).
        # An empty/invalid map resolves nothing.
        def self.parse(json)
          data = json.to_s.strip.empty? ? {} : (JSON.parse(json) rescue {})
          new(data.is_a?(Hash) ? data : {})
        end

        def initialize(data = {})
          @imports = data["imports"].is_a?(Hash) ? data["imports"] : {}
          @scopes = data["scopes"].is_a?(Hash) ? data["scopes"] : {}
        end

        def empty? = @imports.empty? && @scopes.empty?

        # Resolve a bare specifier to a URL string, or nil when unmapped. A
        # scope whose prefix matches the importer wins over the top-level
        # `imports`; within each map, an exact key wins over the longest
        # trailing-slash prefix.
        def resolve(specifier, importer = nil)
          scope_map(importer)&.then { |m| match(m, specifier) } || match(@imports, specifier)
        end

        private

        # The scope map whose prefix is the longest match for `importer`.
        def scope_map(importer)
          return nil if importer.nil? || @scopes.empty?

          key = @scopes.keys.select { |prefix| importer.to_s.start_with?(prefix) }.max_by(&:length)
          key && @scopes[key]
        end

        def match(map, specifier)
          return map[specifier] if map.key?(specifier)

          # Longest trailing-slash prefix: `{"foo/": "/assets/foo/"}` maps
          # `foo/bar.js` -> `/assets/foo/bar.js`.
          prefix = map.keys.select { |k| k.end_with?("/") && specifier.start_with?(k) }.max_by(&:length)
          return nil unless prefix

          "#{map[prefix]}#{specifier[prefix.length..]}"
        end
      end
    end
  end
end
