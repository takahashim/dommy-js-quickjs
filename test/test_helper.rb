# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dommy/js/quickjs"
require "dommy"

# Run the bridge suite against either DOM backend, e.g.
#   DOMMY_BACKEND=makiri bundle exec rake test
Dommy::Backend.use(ENV["DOMMY_BACKEND"].to_sym) if ENV["DOMMY_BACKEND"]

require "minitest/autorun"

# A quickjs that reports a promise rejection before a handler can attach (the
# released 0.21.0) has its Ruby rejection reports switched off — see
# Runtime#on_unhandled_rejection — so a test of what an unhandled rejection
# reports has nothing to observe there.
module SkipOnPrematureRejectionReports
  def skip_on_premature_rejection_reports
    return unless Dommy::Js::Quickjs::Backend.premature_rejection_reports?

    skip "this quickjs reports rejections before a handler can attach, so they are not relayed"
  end
end
Minitest::Test.include(SkipOnPrematureRejectionReports)

require_relative "support/browser_harness"
require_relative "support/wpt_harness"
