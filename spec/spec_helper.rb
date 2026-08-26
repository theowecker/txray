# frozen_string_literal: true

require "fileutils"
require "txray"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
end

module AnalysisHelpers
  def analyze(code, config: Txray::Config.new)
    Txray.analyze(code, config: config)
  end

  def rules_for(code, **)
    analyze(code, **).map(&:id)
  end
end

RSpec.configure { |config| config.include AnalysisHelpers }
