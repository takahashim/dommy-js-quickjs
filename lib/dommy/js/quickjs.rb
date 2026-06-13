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

# The engine-agnostic host layer lives in the `dommy` gem (loaded above via
# `require "dommy"`): the Runtime port + registry, ScriptBoot/ImportMap/
# ModuleLoader, Dommy::Browser, AND the JS<->Ruby DOM bridge (HostBridge +
# WireTags / HandleTable / DomInterfaces / ConstructorResolver /
# CustomElementBridge, with host_runtime.js / observable_runtime.js). This gem
# provides only the QuickJS backend that plugs in underneath.
require_relative "quickjs/backend"
require_relative "quickjs/wasm_bridge"
require_relative "quickjs/runtime"
require_relative "quickjs/script_cache"

# Register QuickJS as a pluggable JS runtime backend (the default). The host
# layer builds runtimes through `Dommy::Js.build_runtime` rather than naming
# this class directly.
Dommy::Js.register_runtime(:quickjs) { |**opts| Dommy::Js::Quickjs::Runtime.new(**opts) }
