# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in dommy-js-quickjs.gemspec
gemspec

# SPIKE (module-preload)
gem "quickjs", github: "hmsk/quickjs.rb", ref: "50cc102", submodules: true

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

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
