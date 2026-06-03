# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in dommy-js-quickjs.gemspec
gemspec

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

  # Optional alternative DOM backend (Lexbor-based), for running the suite with
  # DOMMY_BACKEND=makiri. Unpublished; only wired up in the monorepo.
  makiri = File.expand_path("../makiri", __dir__)
  gem "makiri", path: makiri if File.directory?(makiri)
else
  gem "dommy"
end
