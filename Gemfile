# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in dommy-js-quickjs.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

# Local development: use the working trees from the dommy monorepo next door.
gem "dommy", path: "../dommy/gems/dommy"

# Dommy needs a parser backend at runtime; pick nokogiri for tests.
gem "nokogiri"

# Test-only: exercise the optional Capybara adapter end to end.
gem "capybara"
gem "capybara-dommy", path: "../dommy/gems/capybara-dommy"
gem "dommy-rack", path: "../dommy/gems/dommy-rack"
