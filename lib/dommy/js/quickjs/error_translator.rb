# frozen_string_literal: true

module Dommy
  module Js
    module Quickjs
      # Turns what the ENGINE raised into what the page (or the host) should see.
      #
      # QuickJS converts a JS throw into a Ruby exception before the host hears
      # about it, which loses the thrown object, and a rejection reason the
      # engine could only stringify arrives as "[object Object]". Each of those
      # needs a different repair, and none of them is about running scripts or
      # driving the loop, so they live here rather than in Runtime.
      class ErrorTranslator
        # An engine frame in a converted exception's backtrace (`at f
        # (<code>:1:34)`). A host-raised one carries Ruby frames instead
        # (`/…/lib/dommy/js/quickjs/backend.rb:82:in '…'`).
        #
        # Core has a stricter counterpart (Internal::ExceptionReport::STACK_FRAME)
        # that PARSES a frame into file/line/column for ErrorEvent. This one only
        # asks whether a frame came from JS at all, and stays here because the
        # answer is engine-specific: what a frame looks like is QuickJS's
        # business, and another backend's would differ.
        JS_FRAME = /\A\s*at\s/
        private_constant :JS_FRAME

        def initialize(backend, bridge)
          @backend = backend
          @bridge = bridge
        end

        # Rebuild a script's thrown value as a real Error inside the realm.
        #
        # QuickJS raises a HOST exception when an evaluated script throws, so by
        # the time we see it the JS value is gone: its message and frames survive
        # as a Ruby exception, the object itself does not. Handing that husk to
        # the page gives a handler an object with no `message` and no `stack`,
        # which is worse than useless — reading either throws, so the handler
        # dies before it can cancel the report.
        #
        # An equivalent Error is built in the realm instead, carrying the same
        # name, message and frames. Everything a handler observes matches what it
        # threw; what it cannot do is compare identity (`e.error === thrown`),
        # since the original was freed before we were told about it. Preserving
        # that needs the engine to hand the value over instead of converting it.
        #
        # Returns nil for anything that did not come from JS (a host bug) and for
        # any failure to rebuild, so the caller falls back to what it caught.
        def rebuild_error(error)
          return nil unless error.is_a?(::Quickjs::RuntimeError)

          # Deliberately NOT through an evaluate that drives the event loop: this
          # runs while the page is still booting its scripts, and a due-now timer
          # from an earlier script would fire before the next `<script>`, which
          # no browser does. Calling the realm's helper (see js/error_rebuild.js)
          # only builds the object and marshals it.
          @bridge.decode(
            @backend.call_js("__rbDommyRebuildError",
              js_error_name(error), error.message.to_s, js_frames(error))
          )
        rescue ::StandardError
          nil
        end

        # The JS half of a converted exception's backtrace, as the page's own
        # `stack` string.
        #
        # Handing the host frames to the page would publish this gem's file paths
        # to anything that reads `error.stack` — a page can log or upload it.
        # Keep the JS frames, drop the rest, and let an all-host backtrace
        # produce an empty stack rather than a plausible-looking lie about where
        # the page failed.
        def js_frames(error)
          Array(error.backtrace).grep(JS_FRAME).join("\n")
        end

        # In rejection-debug mode, replace the engine's detail-less "[object
        # Object]" message (a non-Error reason the engine could only toString)
        # with the rich detail recorded JS-side at rejection time, paired by
        # recency. A no-op for errors that already carry a real message.
        def enrich_rejection(error)
          return error unless error.respond_to?(:message) && error.message.to_s.strip == "[object Object]"

          detail = @bridge.take_rejection_detail
          return error if detail.nil? || detail.to_s.empty?

          enriched = ::Quickjs::RuntimeError.new(detail.to_s, "UnhandledRejection")
          enriched.set_backtrace(error.backtrace) if error.backtrace
          enriched
        rescue ::StandardError
          error
        end

        # Attach the timer's scheduling stack (where the page set the timer up)
        # to the error, so a callback that throws a stackless value — a bare
        # `null`, common in minified bundles — is still traceable to the code
        # that scheduled it. The error's class (and message, the dedup key) is
        # kept; only its backtrace is replaced with the JS frames, which the
        # diagnostics UI reads in place of the host scheduler internals. A no-op
        # when no origin was captured (a timer not created through the
        # instrumented globals, or a unit test driving the scheduler directly).
        def with_timer_origin(error, timer)
          frames = timer_origin(timer)
          error.set_backtrace(frames) unless frames.empty?
          error
        rescue ::StandardError
          error
        end

        private

        # The JS constructor name behind a converted exception. quickjs.rb maps
        # each standard error to its own subclass (`Quickjs::TypeError` for a JS
        # `TypeError`), and uses the generic `RuntimeError` for a plain `Error`
        # and for a thrown non-Error.
        def js_error_name(error)
          name = error.class.name.to_s.split("::").last.to_s
          name == "RuntimeError" ? "Error" : name
        end

        # The scheduling stack for `timer`, as cleaned frame strings (or []). The
        # origin Error lives JS-side (see js/timer_globals.js) until now;
        # fetching it also clears it.
        def timer_origin(timer)
          return [] unless timer.respond_to?(:id)

          stack = @backend.call_js("__rbFetchTimerOrigin", timer.id).to_s
          # Drop the shim's own frame (the `new Error()` in __rbDefer) so the top
          # frame is the page code that called setTimeout/setInterval.
          stack.split("\n").map(&:strip).reject(&:empty?)
               .reject { |line| line.include?("__rbDefer") }
        rescue ::StandardError
          []
        end
      end
    end
  end
end
