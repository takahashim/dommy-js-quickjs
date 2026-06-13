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

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "quickjs", "~> 0.18.0"
  spec.add_dependency "dommy", ">= 0.9.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
