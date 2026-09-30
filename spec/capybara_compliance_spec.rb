# frozen_string_literal: true

# Capybara's driver compliance suite (Capybara::SpecHelper, with its bundled
# Sinatra TestApp) run against capybara-dommy's driver with JavaScript on —
# the `javascript: true` path this gem provides. capybara-dommy runs the same
# suite against its JS-free driver; this is the JS-enabled half, which lives
# here because dommy does not depend on this gem.
#
# Not part of `rake test` (the suite still has failures); run it with
#
#   rake capybara:compliance
#
# It needs its own process: requiring the JS adapter turns JavaScript on for
# every Capybara::Dommy::Driver in the process.

require "dommy/js/quickjs/capybara"
require "capybara/spec/spec_helper"

# Sinatra 4 enables host authorization by default, which 403s the
# www.example.com host Capybara uses. Disable it for the bundled TestApp
# (before the first request builds the middleware stack).
if defined?(TestApp) && TestApp.respond_to?(:host_authorization)
  TestApp.set(:host_authorization, permitted_hosts: [])
end

Capybara.register_driver(:dommy_js) do |app|
  Capybara::Dommy::Driver.new(app, javascript: true, default_host: Capybara.default_host)
end

RSpec.configure do |config|
  Capybara::SpecHelper.configure(config)
end

module TestSessions
  DommyJs = Capybara::Session.new(:dommy_js, TestApp)
end

# Capabilities the JS-enabled driver still does not provide. `js`, `modals` and
# `shadow_dom` are NOT here: execute_script / evaluate_script run for real, the
# native dialog helpers work, and shadow_dom's spec obtains its element via
# evaluate_script. What stays out is geometry (no layout engine), a real server /
# download, and live cross-window frame switching.
skipped_tests = %i[
  windows
  screenshot
  scroll
  spatial
  hover
  download
  server
]

Capybara::SpecHelper.run_specs(TestSessions::DommyJs, "DommyJs", capybara_skip: skipped_tests) do |example|
  case example.metadata[:full_description]
  when /obscured/
    skip "Element#obscured? needs geometry (no layout engine)"
  when /#assert_matches_style should raise error/, /:style option should support Hash/
    skip "Asserts the exact Hash#inspect failure-message format, which changed in Ruby 3.4"
  end
end
