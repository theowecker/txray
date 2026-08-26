# frozen_string_literal: true

RSpec.describe Txray::ScopeFinder do
  it "treats callbacks that run inside the save transaction as transactional" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_create :charge

        def charge
          Stripe::Charge.create(amount: total)
        end
      end
    RUBY
    offense = analyze(code).first
    expect(offense.id).to eq("external-service-in-transaction")
    expect(offense.scope.label).to eq("the `after_create :charge` callback")
  end

  it "leaves after_commit callbacks alone" do
    code = <<~RUBY
      class Order < ApplicationRecord
        after_commit :charge, on: :create

        def charge
          Stripe::Charge.create(amount: total)
        end
      end
    RUBY
    expect(analyze(code)).to be_empty
  end

  it "handles callbacks written as blocks" do
    code = <<~RUBY
      class Order < ApplicationRecord
        before_save do
          Faraday.post(url)
        end
      end
    RUBY
    expect(rules_for(code)).to eq([ "http-in-transaction" ])
  end

  it "treats with_lock blocks as transactional" do
    code = <<~RUBY
      class Order < ApplicationRecord
        def settle
          with_lock do
            Faraday.post(url)
          end
        end
      end
    RUBY
    expect(rules_for(code)).to eq([ "http-in-transaction" ])
  end

  it "treats a method that locks a row as transactional" do
    code = <<~RUBY
      class Order < ApplicationRecord
        def settle
          lock!
          Twilio::REST::Client.new.messages.create(to: phone)
        end
      end
    RUBY
    expect(rules_for(code)).to eq([ "external-service-in-transaction" ])
  end

  it "reports the receiver of an explicit transaction" do
    code = <<~RUBY
      class Order < ApplicationRecord
        def settle
          ApplicationRecord.transaction do
            sleep 1
          end
        end
      end
    RUBY
    expect(analyze(code).first.scope.label).to eq("the `ApplicationRecord.transaction` block")
  end
end
