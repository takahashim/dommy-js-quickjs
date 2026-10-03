# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dommy/js/quickjs"
require "dommy"

# Run the bridge suite against either DOM backend, e.g.
#   DOMMY_BACKEND=makiri bundle exec rake test
Dommy::Backend.use(ENV["DOMMY_BACKEND"].to_sym) if ENV["DOMMY_BACKEND"]

require "minitest/autorun"

require_relative "support/browser_harness"
require_relative "support/wpt_harness"
