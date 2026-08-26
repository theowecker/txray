# frozen_string_literal: true

RSpec.describe Txray::Analyzer do
  it "follows helper methods called from a transaction" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_create :notify

        def notify
          push_to_crm
        end

        def push_to_crm
          Faraday.post(crm_url, payload)
        end
      end
    RUBY
    offense = analyze(code).first
    expect(offense.id).to eq("http-in-transaction")
    expect(offense.scope.label).to eq("the `after_create :notify` callback")
    expect(offense.trace.map(&:label)).to eq([ "Order#push_to_crm" ])
  end

  it "stops following once the depth limit is reached" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_create :one
        def one = two
        def two = three
        def three = four
        def four = Faraday.post(url)
      end
    RUBY
    expect(rules_for(code, config: Txray::Config.new("max_depth" => 2))).to be_empty
    expect(rules_for(code, config: Txray::Config.new("max_depth" => 5))).to eq([ "http-in-transaction" ])
  end

  it "survives mutually recursive methods" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_create :ping
        def ping = pong
        def pong = ping
      end
    RUBY
    expect(analyze(code)).to be_empty
  end

  it "resolves methods provided by an included concern" do
    code = <<~RUBY
      module Chargeable
        def charge
          Stripe::Charge.create(amount: total)
        end
      end

      class Order < ApplicationRecord
        include Chargeable
        after_create :charge
      end
    RUBY
    offense = analyze(code).first
    expect(offense.id).to eq("external-service-in-transaction")
    expect(offense.scope.label).to eq("the `after_create :charge` callback")
  end

  it "reports each offending call once" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_create :charge

        def charge
          transaction do
            Faraday.post(url)
          end
        end
      end
    RUBY
    expect(analyze(code).size).to eq(1)
  end

  it "respects disabled rules" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_create :charge
        def charge = Faraday.post(url)
      end
    RUBY
    config = Txray::Config.new("disabled_rules" => [ "http-in-transaction" ])
    expect(analyze(code, config: config)).to be_empty
  end

  it "sorts the highest severity first" do
    code = <<~RUBY
      class Order < ApplicationRecord
        def settle
          transaction do
            Rails.cache.fetch(key)
            Faraday.post(url)
          end
        end
      end
    RUBY
    expect(analyze(code).map(&:severity)).to eq(%i[high low])
  end
end
