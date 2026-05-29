# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in dommy-js-quickjs.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

# Local development: use the working trees next to this gem.
gem "quickjs", path: "/Users/maki/git/quickjs.rb"
gem "dommy", path: "../dommy"

# Dommy needs a parser backend at runtime; pick nokogiri for tests.
gem "nokogiri"

# Test-only: exercise the optional Capybara adapter end to end.
gem "capybara"
gem "capybara-dommy", path: "/Users/maki/git/capybara-dommy"
gem "dommy-rack", path: "/Users/maki/git/dommy-rack"
