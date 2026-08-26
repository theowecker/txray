# frozen_string_literal: true

RSpec.describe "transaction scenarios" do
  def scenario(code) = analyze(code).map { |o| [ o.id, o.scope.label ] }

  describe "implicit callback transactions" do
    {
      "before_validation" => "Faraday.get(geocode_url)",
      "before_save" => "Stripe::Customer.update(stripe_id, {})",
      "before_create" => "Net::HTTP.get(uri)",
      "before_update" => "HTTParty.post(url)",
      "before_destroy" => 'system("rm -rf tmp")',
      "after_validation" => "sleep 1",
      "after_save" => "Aws::S3::Client.new.put_object(bucket: b)",
      "after_create" => "ShipJob.perform_later(self)",
      "after_update" => "Mailer.changed(self).deliver_now",
      "after_destroy" => "Redis.new.del(cache_key)",
      "after_touch" => "Rails.cache.delete(cache_key)",
      "around_save" => "Twilio::REST::Client.new.messages.create(to: phone)",
      "around_create" => "`convert in.png out.png`",
      "around_update" => "Timeout.timeout(5) { poll }",
      "around_destroy" => "Octokit.delete(repo)"
    }.each do |callback, call|
      it "flags #{call.split(/[.(\s]/).first} inside #{callback}" do
        code = <<~RUBY
          class Order < ApplicationRecord
            #{callback} :work
            def work = #{call}
          end
        RUBY
        expect(scenario(code)).to contain_exactly([ anything, "the `#{callback} :work` callback" ])
      end
    end
  end

  describe "callbacks that run after the transaction commits" do
    %w[after_commit after_create_commit after_update_commit after_save_commit after_destroy_commit after_rollback]
      .each do |callback|
      it "leaves #{callback} alone" do
        code = <<~RUBY
          class Order < ApplicationRecord
            #{callback} :work
            def work = Faraday.post(url)
          end
        RUBY
        expect(analyze(code)).to be_empty
      end
    end
  end

  describe "explicit transaction blocks" do
    it "flags calls in a bare transaction block" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def settle
            transaction { Stripe::Refund.create(id) }
          end
        end
      RUBY
      expect(scenario(code)).to eq([ [ "external-service-in-transaction", "an explicit `transaction` block" ] ])
    end

    it "flags calls in an ActiveRecord::Base transaction" do
      code = <<~RUBY
        class Importer
          def call
            ActiveRecord::Base.transaction(requires_new: true) do
              Faraday.get(feed_url)
            end
          end
        end
      RUBY
      expect(scenario(code)).to eq([ [ "http-in-transaction", "the `ActiveRecord::Base.transaction` block" ] ])
    end

    it "flags calls inside a class method transaction" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def self.import(rows)
            transaction do
              rows.each { |row| create!(row) }
              Slack::Web::Client.new.chat_postMessage(text: "imported")
            end
          end
        end
      RUBY
      expect(scenario(code).map(&:first))
        .to contain_exactly("external-service-in-transaction", "iteration-in-transaction")
    end

    it "flags calls in a nested service object transaction" do
      code = <<~RUBY
        class Checkout
          def perform
            ApplicationRecord.transaction do
              order.save!
              charge
            end
          end

          private

          def charge
            Stripe::PaymentIntent.create(amount: total)
          end
        end
      RUBY
      expect(scenario(code)).to eq([ [ "external-service-in-transaction", "the `ApplicationRecord.transaction` block" ] ])
    end
  end

  describe "locks" do
    it "flags calls in a with_lock block" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def settle
            with_lock { Faraday.post(url) }
          end
        end
      RUBY
      expect(scenario(code)).to eq([ [ "http-in-transaction", "a `with_lock` block" ] ])
    end

    it "flags calls after an explicit lock!" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def settle
            lock!
            Sidekiq::Client.push("class" => ShipJob, "args" => [ id ])
          end
        end
      RUBY
      expect(scenario(code)).to eq([ [ "job-enqueue-in-transaction", "`Order#settle`, which locks a row" ] ])
    end
  end

  describe "long running work" do
    it "flags batched iteration that writes per row" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def backfill
            transaction do
              Order.find_each { |order| order.update!(state: :done) }
            end
          end
        end
      RUBY
      expect(scenario(code).map(&:first)).to eq([ "iteration-in-transaction" ])
    end

    it "flags attachment uploads in a callback" do
      code = <<~RUBY
        class Photo < ApplicationRecord
          before_save :store
          def store = original.attach(io: file, filename: name)
        end
      RUBY
      expect(scenario(code).map(&:first)).to eq([ "upload-in-transaction" ])
    end
  end

  describe "call graph resolution" do
    it "follows several callbacks declared on one line" do
      code = <<~RUBY
        class Order < ApplicationRecord
          after_create :charge, :notify
          def charge = Stripe::Charge.create(amount: total)
          def notify = Faraday.post(url)
        end
      RUBY
      expect(scenario(code).map(&:first))
        .to contain_exactly("external-service-in-transaction", "http-in-transaction")
    end

    it "ignores conditional symbols passed as keywords" do
      code = <<~RUBY
        class Order < ApplicationRecord
          after_create :charge, if: :chargeable?
          def charge = total
          def chargeable? = Faraday.get(url).success?
        end
      RUBY
      expect(analyze(code)).to be_empty
    end

    it "follows self dot calls into singleton methods" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def self.sweep
            transaction { self.notify_ops }
          end

          def self.notify_ops = Slack::Web::Client.new.chat_postMessage(text: "swept")
        end
      RUBY
      expect(scenario(code).map(&:first)).to eq([ "external-service-in-transaction" ])
    end

    it "resolves callbacks registered from a concern included block" do
      code = <<~RUBY
        module Syncable
          extend ActiveSupport::Concern

          included do
            after_save :sync_remote
          end

          def sync_remote = Faraday.put(remote_url, to_json)
        end
      RUBY
      expect(scenario(code)).to eq([ [ "http-in-transaction", "the `after_save :sync_remote` callback" ] ])
    end

    it "follows a service object instantiated inside a transaction" do
      code = <<~RUBY
        class Checkout
          def initialize(order) = @order = order

          def call
            Stripe::PaymentIntent.create(amount: @order.total)
          end
        end

        class Order < ApplicationRecord
          def settle
            transaction { Checkout.new(self).call }
          end
        end
      RUBY
      offense = analyze(code).first
      expect(offense.id).to eq("external-service-in-transaction")
      expect(offense.trace.map(&:label)).to eq([ "Checkout#call" ])
    end

    it "follows a class method on another constant" do
      code = <<~RUBY
        module Ledger
          def self.record(order)
            InternalApi::Ledger.post(order)
          end
        end

        class Order < ApplicationRecord
          after_create :post_to_ledger
          def post_to_ledger = Ledger.record(self)
        end
      RUBY
      config = Txray::Config.new("external_clients" => [ "InternalApi" ])
      offense = analyze(code, config: config).first
      expect(offense.id).to eq("external-service-in-transaction")
      expect(offense.trace.map(&:label)).to eq([ "Ledger.record" ])
    end

    it "namespaces classes correctly" do
      code = <<~RUBY
        module Billing
          class Invoice < ApplicationRecord
            after_create :charge
            def charge = Stripe::Charge.create(amount: total)
          end
        end
      RUBY
      expect(analyze(code).first.trace).to be_empty
      expect(scenario(code).map(&:first)).to eq([ "external-service-in-transaction" ])
    end
  end

  describe "code that should stay quiet" do
    it "ignores external calls outside any transaction" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def refresh
            Stripe::Charge.retrieve(charge_id)
            Faraday.get(url)
            ReceiptMailer.paid(self).deliver_now
          end
        end
      RUBY
      expect(analyze(code)).to be_empty
    end

    it "ignores plain database work inside a transaction" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def settle
            transaction do
              update!(state: :settled)
              line_items.update_all(settled: true)
              Payment.create!(order: self, amount: total)
            end
          end
        end
      RUBY
      expect(analyze(code)).to be_empty
    end

    it "ignores loops with no database work inside a transaction" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def settle
            transaction do
              total = line_items.sum { |item| item.price * item.quantity }
              update!(total: total)
            end
          end
        end
      RUBY
      expect(analyze(code)).to be_empty
    end
  end
end
