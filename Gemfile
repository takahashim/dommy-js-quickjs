# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in dommy-js-quickjs.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

# TEMPORARY: the released quickjs (0.21.0) reports an unhandled rejection the
# moment a promise rejects, rather than at the end of the microtask checkpoint
# as HTML requires. Correct code is misreported — `Promise.reject(x).catch(...)`
# and `try { await rejecting() } catch {}` both attach their handler later in
# the same checkpoint — which a strict host then fails a test on. The fork
# branch that implements HTML's timing is open upstream as
# https://github.com/hmsk/quickjs.rb/pull/141; pinned one commit past it, to
# `feat/rejection-js-hook`, which hands rejections to a JS function with the
# promise and reason intact — without it the window's `event.reason` /
# `event.promise` / `rejectionhandled` have nothing to report and their tests
# skip. That branch has no upstream PR yet. Drop the override (and relax the
# gemspec) once both are released.
gem "quickjs", github: "takahashim/quickjs.rb", ref: "ef60ed5",
  submodules: true # the QuickJS C sources are a submodule

# In the dommy monorepo, use the working trees next door; a standalone clone
# (CI included) falls back to dommy's main on GitHub. Both sides carry the same set,
# so CI runs the Capybara and Rack suites too rather than skipping 60 tests.
dommy_gems = File.expand_path("../dommy/gems", __dir__)
if File.directory?(dommy_gems)
  gem "dommy", path: "#{dommy_gems}/dommy"

  # Test-only Capybara integration.
  gem "capybara"
  gem "capybara-dommy", path: "#{dommy_gems}/capybara-dommy"
  gem "dommy-rack", path: "#{dommy_gems}/dommy-rack"

  # DOM parser backend (Lexbor-based) — a dependency of dommy, resolved from
  # RubyGems (>= 0.7.0). For makiri development, uncomment the path override to
  # test a local sibling checkout against this suite.
  # gem "makiri", path: File.expand_path("../makiri", __dir__)
else
  # This gem tracks dommy's main (the bridge wire tags, Location's exotic
  # shape), which runs ahead of the released gems; pull the monorepo from
  # GitHub so CI tests against what the working tree does.
  git "https://github.com/takahashim/dommy.git", branch: "main", glob: "gems/*/*.gemspec" do
    gem "dommy"
    gem "capybara-dommy"
    gem "dommy-rack"
  end

  gem "capybara"
end
