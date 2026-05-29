# frozen_string_literal: true

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
require_relative "host_bridge"
require_relative "quickjs/backend"
require_relative "quickjs/runtime"
