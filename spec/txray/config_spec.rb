# frozen_string_literal: true

require "tmpdir"

RSpec.describe Txray::Config do
  it "falls back to defaults" do
    config = described_class.new
    expect(config.includes).to eq([ "app", "lib", "db/migrate" ])
    expect(config.max_depth).to eq(3)
    expect(config.fail_level).to eq(:low)
  end

  it "deep merges the runtime section" do
    config = described_class.new("runtime" => { "enabled" => true })
    expect(config.runtime).to include("enabled" => true, "threshold_ms" => 250)
  end

  it "reads a yaml file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".txray.yml")
      File.write(path, "include:\n  - engines\nexternal_clients:\n  - InternalApi\n")
      config = described_class.load(path)
      expect(config.includes).to eq([ "engines" ])
      expect(config.external_clients).to eq([ "InternalApi" ])
    end
  end

  it "treats configured clients as external services" do
    code = <<~RUBY
      class Order < ApplicationRecord
        def settle
          transaction { InternalApi::Ledger.post(self) }
        end
      end
    RUBY
    config = described_class.new("external_clients" => [ "InternalApi" ])
    expect(rules_for(code, config: config)).to eq([ "external-service-in-transaction" ])
  end

  it "ignores unknown rules in disabled_rules" do
    expect(described_class.new("disabled_rules" => [ "nope" ]).rule_enabled?("http-in-transaction")).to be(true)
  end
end
