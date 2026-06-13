# frozen_string_literal: true

require "dommy"
require_relative "quickjs/version"

module Dommy
  module Js
    module Quickjs
      class Error < StandardError; end
    end
  end
end

# The engine-agnostic host layer (Dommy::Js::Runtime port + registry,
# ScriptBoot/ImportMap/ModuleLoader, Dommy::Browser) lives in the `dommy` gem,
# loaded above via `require "dommy"`. This gem provides the QuickJS backend.
require_relative "wire_tags"
require_relative "handle_table"
require_relative "dom_interfaces"
require_relative "constructor_registry"
require_relative "custom_elements"
require_relative "host_bridge"
require_relative "quickjs/backend"
require_relative "quickjs/wasm_bridge"
require_relative "quickjs/runtime"
require_relative "quickjs/script_cache"

# Register QuickJS as a pluggable JS runtime backend (the default). The host
# layer builds runtimes through `Dommy::Js.build_runtime` rather than naming
# this class directly.
Dommy::Js.register_runtime(:quickjs) { |**opts| Dommy::Js::Quickjs::Runtime.new(**opts) }
