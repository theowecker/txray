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

RSpec.describe "directive regions" do
  def wrapped(body)
    <<~RUBY
      class Order < ApplicationRecord
        def settle
          transaction do
      #{body.lines.map { |line| "      #{line}" }.join}
          end
        end
      end
    RUBY
  end

  it "disables a region between disable and enable" do
    code = wrapped(<<~RUBY)
      # txray:disable http-in-transaction
      Faraday.post(url)
      # txray:enable http-in-transaction
      Faraday.get(url)
    RUBY
    expect(analyze(code).map(&:line)).to eq([ 7 ])
  end

  it "runs a region to the end of the file without an enable" do
    code = wrapped(<<~RUBY)
      # txray:disable http-in-transaction
      Faraday.post(url)
      Faraday.get(url)
    RUBY
    expect(analyze(code)).to be_empty
  end

  it "only disables the rules the region names" do
    code = wrapped(<<~RUBY)
      # txray:disable cache-in-transaction
      Faraday.post(url)
      # txray:enable cache-in-transaction
    RUBY
    expect(analyze(code).map(&:id)).to eq([ "http-in-transaction" ])
  end

  it "disables every rule for a bare region" do
    code = wrapped(<<~RUBY)
      # txray:disable
      Faraday.post(url)
      ShipJob.perform_later(self)
      # txray:enable
    RUBY
    expect(analyze(code)).to be_empty
  end

  it "treats disable all as every rule" do
    code = wrapped(<<~RUBY)
      # txray:disable all
      Faraday.post(url)
    RUBY
    expect(analyze(code)).to be_empty
  end

  it "disables a whole file from a directive at the top" do
    code = <<~RUBY
      # txray:disable all
      class Order < ApplicationRecord
        after_create :charge
        def charge = Faraday.post(url)
      end
    RUBY
    expect(analyze(code)).to be_empty
  end

  it "re-enables one rule while leaving another disabled" do
    code = wrapped(<<~RUBY)
      # txray:disable http-in-transaction, job-enqueue-in-transaction
      Faraday.post(url)
      # txray:enable job-enqueue-in-transaction
      ShipJob.perform_later(self)
      Faraday.get(url)
    RUBY
    expect(analyze(code).map(&:id)).to eq([ "job-enqueue-in-transaction" ])
  end

  it "does not let a trailing comment leak onto later lines" do
    code = wrapped(<<~RUBY)
      Faraday.post(url) # txray:disable
      Faraday.get(url)
    RUBY
    expect(analyze(code).map(&:line)).to eq([ 5 ])
  end
end
