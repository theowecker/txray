# frozen_string_literal: true

RSpec.describe Txray::Classifier do
  def in_transaction(body)
    <<~RUBY
      class Order < ApplicationRecord
        def settle
          transaction do
            #{body}
          end
        end
      end
    RUBY
  end

  it "flags plain http requests" do
    expect(rules_for(in_transaction("Net::HTTP.post_form(uri, {})"))).to eq([ "http-in-transaction" ])
  end

  it "flags http client libraries" do
    expect(rules_for(in_transaction("Faraday.get(url)"))).to eq([ "http-in-transaction" ])
  end

  it "flags third party service clients" do
    expect(rules_for(in_transaction("Stripe::Charge.create(amount: 100)"))).to eq([ "external-service-in-transaction" ])
  end

  it "flags synchronous mail delivery" do
    expect(rules_for(in_transaction("ReceiptMailer.paid(self).deliver_now"))).to eq([ "mail-in-transaction" ])
  end

  it "flags job enqueues that can outrun the commit" do
    expect(rules_for(in_transaction("ShipJob.perform_later(self)"))).to eq([ "job-enqueue-in-transaction" ])
  end

  it "flags subprocesses" do
    expect(rules_for(in_transaction('system("convert in.png out.png")'))).to eq([ "shell-in-transaction" ])
  end

  it "flags backticks" do
    expect(rules_for(in_transaction("`pdftotext file.pdf`"))).to eq([ "shell-in-transaction" ])
  end

  it "flags deliberate blocking" do
    expect(rules_for(in_transaction("sleep 2"))).to eq([ "sleep-in-transaction" ])
  end

  it "flags attachment uploads" do
    expect(rules_for(in_transaction("avatar.attach(file)"))).to eq([ "upload-in-transaction" ])
  end

  it "flags cache round trips at low severity" do
    offenses = analyze(in_transaction("Rails.cache.fetch(key) { compute }"))
    expect(offenses.map(&:id)).to eq([ "cache-in-transaction" ])
    expect(offenses.first.severity).to eq(:low)
  end

  it "flags loops that write per iteration" do
    expect(rules_for(in_transaction("items.each { |item| item.save! }"))).to eq([ "iteration-in-transaction" ])
  end

  it "ignores loops with no database work" do
    expect(rules_for(in_transaction("items.each { |item| total += item.price }"))).to be_empty
  end

  it "ignores ordinary work" do
    expect(rules_for(in_transaction("update!(state: :settled)"))).to be_empty
  end

  it "ignores the same calls outside a transaction" do
    code = <<~RUBY
      class Order < ApplicationRecord
        def settle
          Net::HTTP.post_form(uri, {})
        end
      end
    RUBY
    expect(rules_for(code)).to be_empty
  end
end
