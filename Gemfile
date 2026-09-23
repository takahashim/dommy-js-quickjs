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
# the same checkpoint — which a strict host then fails a test on. Pinned to the
# fork branch that implements HTML's timing, open upstream as
# https://github.com/hmsk/quickjs.rb/pull/141. Drop the override (and relax the
# gemspec) once it is released.
gem "quickjs", github: "takahashim/quickjs.rb", ref: "668d4c1",
  submodules: true # the QuickJS C sources are a submodule

# In the dommy monorepo, use the working trees next door; a standalone clone
# falls back to the released gems.
dommy_gems = File.expand_path("../dommy/gems", __dir__)
if File.directory?(dommy_gems)
  gem "dommy", path: "#{dommy_gems}/dommy"

  # Test-only Capybara integration (these gems are unpublished).
  gem "capybara"
  gem "capybara-dommy", path: "#{dommy_gems}/capybara-dommy"
  gem "dommy-rack", path: "#{dommy_gems}/dommy-rack"

  # DOM parser backend (Lexbor-based) — a dependency of dommy, resolved from
  # RubyGems (>= 0.7.0). For makiri development, uncomment the path override to
  # test a local sibling checkout against this suite.
  # gem "makiri", path: File.expand_path("../makiri", __dir__)
else
  gem "dommy"
end
