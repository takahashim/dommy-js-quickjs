# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dommy/js/quickjs"
require "dommy"

require "minitest/autorun"

require_relative "support/browser_harness"
