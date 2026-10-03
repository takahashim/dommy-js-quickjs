# frozen_string_literal: true

require_relative "lib/dommy/js/quickjs/version"

Gem::Specification.new do |spec|
  spec.name = "dommy-js-quickjs"
  spec.version = Dommy::Js::Quickjs::VERSION
  spec.authors = ["takahashim"]
  spec.email = ["takahashimm@gmail.com"]

  spec.summary = "QuickJS backend for running JavaScript against a Dommy DOM."
  spec.description = <<~DESC
    dommy-js-quickjs lets JavaScript drive a Dommy DOM by embedding QuickJS (via
    the quickjs gem) and bridging DOM nodes to JS through an ES Proxy that routes
    property/method access into Dommy's __js_get__ / __js_set__ / __js_call__ ABI.
  DESC
  spec.homepage = "https://github.com/takahashim/dommy-js-quickjs"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # What a user needs, listed rather than everything git tracks minus a few, so
  # a new script, spec or CI file stays out of the package without a thought.
  spec.files = Dir.glob(%w[lib/**/* sig/**/* README.md CHANGELOG.md LICENSE.txt], base: __dir__)
                  .select { |f| File.file?(File.join(__dir__, f)) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # NOTE: 0.22.0 is the first release that reports an unhandled rejection at
  # the end of the microtask checkpoint, as HTML does (hmsk/quickjs.rb#141).
  # The JS rejection hook is still unreleased; the Gemfile pins a fork carrying
  # it, and gemfiles/quickjs-released.gemfile tests the release.
  spec.add_dependency "quickjs", "~> 0.22.0"
  spec.add_dependency "dommy", ">= 0.14.0", "< 0.15"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
