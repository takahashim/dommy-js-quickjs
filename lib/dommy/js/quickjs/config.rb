# frozen_string_literal: true

module Dommy
  module Js
    module Quickjs
      # Every environment variable this backend reads, in one place. They used to
      # be read where they were needed — three files, three layers — so the only
      # way to learn which knobs exist was to grep for `ENV`.
      #
      # Read at the point of use rather than memoized: a test (and dommynx)
      # changes these between runtimes in the same process.
      module Config
        # The gem's default eval timeout is 100ms, which interrupts large
        # synchronous bridge loops (every property crossing is a Ruby call).
        DEFAULT_TIMEOUT_MSEC = 60_000

        # The gem's default memory ceiling is 128 MB. A real-site SPA (note.com's
        # Apollo/React bundle, hydration, the whole DOM mirrored as host proxies)
        # blows past that and the VM hits out-of-memory, which poisons it. Give a
        # browser-grade VM more headroom so heavy pages actually finish
        # rendering; the OOM is also survivable (see Backend#poisoned?).
        DEFAULT_MEMORY_LIMIT = 512 * 1024 * 1024

        module_function

        # The per-eval timeout, in ms. A single JS eval — a script, or one
        # timer/rAF callback — is force-aborted (Quickjs::InterruptedError,
        # caught and logged) after this long. It is ALSO the ceiling on how long
        # QuickJS holds the thread in C: while it runs, a Ctrl-C (delivered as a
        # deferred SIGINT) can't be serviced, so an interactive host (dommynx)
        # sets a lower value so a heavy/runaway burst can't freeze the UI for the
        # full library default.
        def timeout_msec
          env = ENV["DOMMY_JS_TIMEOUT_MSEC"].to_i
          env.positive? ? env : DEFAULT_TIMEOUT_MSEC
        end

        # The VM's memory ceiling, in bytes. Overridable like the timeout, in MB
        # for legibility: an out-of-memory poisons the VM and stops the page's
        # JavaScript for good, so being able to lower it is how that path gets
        # exercised deliberately (and to raise it for a heavier page than the
        # default was sized for).
        def memory_limit
          mb = ENV["DOMMY_JS_MEMORY_LIMIT_MB"].to_i
          mb.positive? ? mb * 1024 * 1024 : DEFAULT_MEMORY_LIMIT
        end

        # Whether to keep the gem's per-crossing Ruby `Timeout.timeout` (see
        # Backend's SkipCrossingTimeout). Off by default: it costs ~4us on every
        # DOM crossing, and QuickJS's own interrupt handler already bounds a
        # runaway execution.
        def crossing_timeout? = !ENV["DOMMY_JS_CROSSING_TIMEOUT"].to_s.empty?

        # Whether to record the JS-side detail of a promise rejection, so a
        # reason the engine could only stringify to "[object Object]" can still
        # be diagnosed (see ErrorTranslator#enrich_rejection). Opt-in: it makes
        # every rejection cross the bridge twice.
        def track_rejections? = !ENV["DOMMY_JS_DEBUG_REJECTIONS"].to_s.empty?
      end
    end
  end
end
