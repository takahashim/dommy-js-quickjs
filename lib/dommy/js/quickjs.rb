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

require_relative "handle_table"
require_relative "dom_interfaces"
require_relative "constructor_registry"
require_relative "custom_elements"
require_relative "host_bridge"
require_relative "quickjs/backend"
require_relative "quickjs/wasm_bridge"
require_relative "quickjs/runtime"
require_relative "quickjs/import_map"
require_relative "quickjs/module_loader"
require_relative "quickjs/script_cache"
require_relative "quickjs/script_boot"
require_relative "../browser"
