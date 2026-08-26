# frozen_string_literal: true

RSpec.describe "inline directives and overrides" do
  it "honours a trailing disable comment" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_create :charge
        def charge = Faraday.post(url) # txray:disable
      end
    RUBY
    expect(analyze(code)).to be_empty
  end

  it "honours a disable comment on the line above" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_create :charge
        def charge
          # txray:disable http-in-transaction
          Faraday.post(url)
        end
      end
    RUBY
    expect(analyze(code)).to be_empty
  end

  it "only disables the rules it names" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_create :charge
        def charge
          # txray:disable cache-in-transaction
          Faraday.post(url)
        end
      end
    RUBY
    expect(analyze(code).map(&:id)).to eq([ "http-in-transaction" ])
  end

  it "applies configured severity overrides" do
    code = <<~RUBY
      class Order < ApplicationRecord
        def settle
          transaction { Rails.cache.fetch(key) }
        end
      end
    RUBY
    config = Txray::Config.new("severities" => { "cache-in-transaction" => "high" })
    expect(analyze(code, config: config).first.severity).to eq(:high)
  end

  it "leaves rules alone without an override" do
    expect(Txray::Config.new.rule("cache-in-transaction").severity).to eq(:low)
  end
end
