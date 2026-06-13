# frozen_string_literal: true

# Wires QuickJS as the JS runtime for `Dommy::Rack::Session.new(app,
# javascript: true)`. Requiring this file (directly, or lazily by the session
# when javascript is requested) registers the :quickjs backend and points the
# session's runtime factory at the realm manager.
#
# The realm manager (Dommy::Rack::SessionRuntime) lives in dommy-rack and is
# backend-agnostic; this gem only supplies the QuickJS engine.
require "dommy/rack"
require_relative "../quickjs"

Dommy::Rack::Session.javascript_runtime_factory = lambda do |session|
  Dommy::Rack::SessionRuntime.new(session)
end
