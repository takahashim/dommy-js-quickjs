# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in dommy-js-quickjs.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

# `rake capybara:compliance` (spec/capybara_compliance_spec.rb) runs Capybara's
# driver compliance suite — RSpec and its bundled Sinatra TestApp — against
# capybara-dommy with JavaScript on. Test-only: the gem itself needs none of
# these.
gem "rspec"
gem "sinatra"
gem "launchy"

# TEMPORARY: the pin is a tag on the fork, the released quickjs 0.22.0 plus one
# commit that hands rejections to a JS function with the promise and reason
# intact — without it the window's `event.reason` / `event.promise` /
# `rejectionhandled` have nothing to report and their tests skip. That commit
# has no upstream PR yet. Drop the override once it is released.
#
# The fork's `feat/rejection-js-hook` is rebased onto each upstream release and
# force-pushed; every rebase gets a tag `v<upstream>-rejection-hook.<n>`, and
# a tag is never moved, so the ref an older commit pins can still be fetched.
#
# gemfiles/quickjs-released.gemfile sets @released_quickjs to skip the pin and
# test against the released gem instead.
unless @released_quickjs
  gem "quickjs", github: "takahashim/quickjs.rb", tag: "v0.22.0-rejection-hook.1",
    submodules: true # the QuickJS C sources are a submodule
end

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
