# frozen_string_literal: true

require "dommy/rack/resources"
require_relative "../quickjs"

module Dommy
  module Js
    module Quickjs
      # Binds a QuickJS runtime to a dommy-rack Session: each HTML document the
      # session loads gets its own JS realm (window globals, listeners, timers),
      # its `<script>` tags boot, and window.fetch / external scripts resolve
      # through the session's Rack app (shared cookie jar). Subscribes to the
      # session's `on_document_loaded` seam so VM lifetime follows page loads.
      #
      # This is the engine behind `Dommy::Rack::Session.new(app, javascript:
      # true)` and the Capybara driver's JS support — one realm manager, two
      # front ends.
      class SessionRuntime
        PUMP_SLICE_MS = 50

        # `current_document` yields the document execute/evaluate should target
        # (the session's current document by default; the Capybara driver passes
        # its own frame-aware accessor).
        # Uncaught JS errors and unhandled promise rejections collected across
        # every realm (a host can fail a test when non-empty), and console output.
        attr_reader :js_errors, :console

        def initialize(session, &current_document)
          @session = session
          @current_document = current_document || -> { session.document }
          @runtimes = {}.compare_by_identity
          @js_errors = []
          @console = []
          session.on_document_loaded { |window| on_page_load(window) }
        end

        def execute(js) = current_runtime.execute(js)
        def evaluate(js) = current_runtime.evaluate(js)

        # Settle work ready at the current virtual time (microtasks + due-now
        # timers + rAF) for the current document's realm.
        def settle
          current_runtime.settle
          self
        end

        # Advance the current realm's virtual clock, running timers that come
        # due, then drain.
        def advance_time(ms)
          scheduler_of(@current_document.call)&.advance_time(ms)
          current_runtime.drain_microtasks
          self
        end

        # Drain the current realm's microtasks (used as an interaction's settle
        # point: a Ruby-dispatched event ran JS handlers; flush their promises).
        def drain
          current_runtime.drain_microtasks
          self
        end

        # Advance virtual time a slice and drain across EVERY live realm, so a
        # timer in any window (top or frame) progresses while a poller waits.
        # Snapshot iteration: a fired timer may navigate and replace the map.
        def pump
          @runtimes.to_a.each do |doc, runtime|
            scheduler_of(doc)&.advance_time(PUMP_SLICE_MS)
            runtime.drain_microtasks
          end
        end

        # The realm VM for one document, built lazily and cached by identity so a
        # frame switch keeps each realm's JS state instead of rebuilding it.
        def runtime_for(doc)
          @runtimes[doc] ||= build_runtime(doc)
        end

        def current_runtime
          runtime_for(@current_document.call)
        end

        def dispose
          dispose_all
        end

        private

        # The deterministic scheduler driving a document's realm (nil when the
        # document or its window is absent), keeping the `doc -> window ->
        # scheduler` walk in one place.
        def scheduler_of(doc)
          doc&.default_view&.scheduler
        end

        # A top-level navigation invalidates every realm (the old documents are
        # gone): dispose all, then eagerly build the new top realm so its
        # window / fetch bridge are live before any script runs.
        def on_page_load(window)
          dispose_all
          runtime_for(window.document)
        end

        def build_runtime(doc)
          rt = Dommy::Js.build_runtime
          rt.on_unhandled_rejection { |err| @js_errors << err }
          rt.on_log { |log| @console << log }
          rt.define_host_object("document", doc)
          if (window = doc&.default_view)
            rt.install_window(window)
            rt.install_browser_globals
            resources = ::Dommy::Rack::Resources.new(@session)
            window.globals["__fetch_handler__"] = ::Dommy::Resources::FetchHandler.new(resources)
            Js::ScriptBoot.run_document_scripts(rt, doc, resources: resources)
          end
          rt
        end

        def dispose_all
          @runtimes.each_value(&:dispose)
          @runtimes = {}.compare_by_identity
        end
      end
    end
  end
end
