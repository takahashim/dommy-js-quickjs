# frozen_string_literal: true

# Wires QuickJS as the JS runtime for `Dommy::Rack::Session.new(app,
# javascript: true)`. Requiring this file (directly, or lazily by the session
# when javascript is requested) registers the runtime factory.
require "dommy/rack"
require_relative "session_runtime"

Dommy::Rack::Session.javascript_runtime_factory = lambda do |session|
  Dommy::Js::Quickjs::SessionRuntime.new(session)
end
