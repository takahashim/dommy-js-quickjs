# frozen_string_literal: true

module Dommy
  module Js
    module Quickjs
      # The WHATWG event loop over two queues that live in different places: the
      # engine's promise-job queue (drained through the Backend) and Dommy's
      # deterministic scheduler (the window's, driven by virtual time).
      #
      # The three entry points differ ONLY in how far they are willing to move
      # the clock, so they share one pump and supply that policy as a block:
      #
      #   #drive_due_now   not at all — whatever is due at this instant
      #   #settle          to the next animation frame, but not to a later timer
      #   #run_until_idle  to the next due timer, repeatedly, until none is left
      #
      # Also the place where a dead VM stops the loop: an out-of-memory poisons
      # the VM, and per the "browsing never crashes" contract the failure is
      # reported once and then swallowed, rather than escaping into a host that
      # is only asking for microtasks to be drained.
      class EventLoop
        # How many due-now turns #drive_due_now takes before giving up. The
        # nested-timer 4ms clamp guarantees due-now work drains in finite turns.
        DUE_NOW_TURNS = 64

        # Bounds a runaway timer loop (a self-rescheduling setInterval, an rAF
        # that always asks for another frame).
        DEFAULT_MAX_ITERATIONS = 1000

        # `on_halt` is called with the exception the first time the VM is found
        # poisoned, and never again.
        def initialize(backend, &on_halt)
          @backend = backend
          @on_halt = on_halt
          @halted = false
        end

        attr_accessor :window

        # Drain the engine's microtask queue. The one operation every policy
        # starts from, and the one a host can ask for on its own.
        def drain_microtasks
          @backend.drain_microtasks
        rescue ::Quickjs::RuntimeError => e
          # The checkpoint hit out-of-memory and poisoned the VM. Record it once
          # (so it shows in js_errors / the activity log) and then no-op — the
          # page's JS is dead, but the browser stays alive.
          raise unless @backend.poisoned?

          note_halted(e)
        end

        # Everything ready at the current virtual time: the microtask checkpoint
        # plus every due task and anything it queues at the same instant, WITHOUT
        # advancing the clock to a future timer (a result waiting on a real delay
        # is left for the caller's await to surface).
        def drive_due_now
          pump(DUE_NOW_TURNS) do |scheduler|
            scheduler.advance_time(0)
            scheduler.next_due_timer_at == scheduler.now_ms
          end
          nil
        end

        # The work that is READY now: microtasks, timers already due
        # (`setTimeout(0)` chains), and pending `requestAnimationFrame`
        # callbacks, reached by advancing to their frame boundary. Does NOT jump
        # the clock to a not-yet-due `setTimeout(300)` — that needs an explicit
        # `advance_time(300)`. The "let promises and animation frames resolve"
        # entry point.
        def settle(max_iterations: DEFAULT_MAX_ITERATIONS)
          pump(max_iterations) do |scheduler|
            before = scheduler.now_ms
            scheduler.advance_time(0) # due-now timers + microtasks, no clock jump
            drain_microtasks

            frame_at = scheduler.next_animation_frame_at
            if frame_at && frame_at > scheduler.now_ms
              scheduler.advance_time(frame_at - scheduler.now_ms) # advance to the frame, run rAF
              next true
            end

            scheduler.now_ms != before # quiescent once the clock stops moving
          end
        end

        # Quiescence: drain, advance to the next due timer, drain again, until no
        # timer is pending. The deterministic "settle everything" a host uses
        # after an eval — every queued microtask runs and every scheduled timer
        # fires, in WHATWG order (microtasks before each timer).
        def run_until_idle(max_iterations: DEFAULT_MAX_ITERATIONS)
          pump(max_iterations) do |scheduler|
            next_at = scheduler.next_due_timer_at
            next false unless next_at

            scheduler.advance_time(next_at - scheduler.now_ms)
            true
          end
        end

        # The VM is poisoned. Surface the failure ONCE (a repeated drain would
        # otherwise report it every tick) so the host sees that the page's
        # JavaScript stopped, then leave it to the no-op guards.
        def note_halted(error)
          return if @halted

          @halted = true
          @on_halt&.call(error)
          nil
        end

        private

        # Drain, then let the policy move the clock; stop when it reports there
        # is nothing left to do, when there is no scheduler to drive, or when the
        # iteration bound runs out.
        def pump(max_iterations)
          scheduler = @window&.scheduler
          max_iterations.times do
            drain_microtasks
            break unless scheduler
            break unless yield(scheduler)

            drain_microtasks
          end
          self
        end
      end
    end
  end
end
