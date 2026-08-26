# frozen_string_literal: true

require_relative "lib/txray/version"

Gem::Specification.new do |spec|
  spec.name = "txray"
  spec.version = Txray::VERSION
  spec.authors = [ "Theo Wecker" ]
  spec.email = [ "tlwecker@yahoo.com" ]

  spec.summary = "Static analysis that finds slow work hidden inside database transactions."
  spec.description = "txray parses your Rails application with Prism and follows callbacks, concerns and helper methods to find HTTP requests, external service clients, mail delivery, job enqueues, subprocesses and unbounded loops running inside database transactions. It needs no application boot and no test coverage, so it reports problems on code paths your suite never executes. An optional runtime guard reports the same problems from a running application."
  spec.homepage = "https://github.com/theowecker/txray"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) || f.start_with?(*%w[bin/ spec/ .github/ .rubocop.yml .gitignore Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = [ "lib" ]

  spec.add_dependency "prism", ">= 0.24"
end
