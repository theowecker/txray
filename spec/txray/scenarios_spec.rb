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

    it "resolves a concern callback whose method lives on the host class" do
      code = <<~RUBY
        module Syncable
          extend ActiveSupport::Concern
          included { after_save :push_remote }
        end

        class Order < ApplicationRecord
          include Syncable
          def push_remote = Faraday.put(url)
        end
      RUBY
      expect(scenario(code)).to eq([ [ "http-in-transaction", "the `after_save :push_remote` callback" ] ])
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

  describe "validations and commit hooks that run inside the save transaction" do
    it "flags a custom validation method" do
      code = <<~RUBY
        class Order < ApplicationRecord
          validate :vat_number_is_real
          def vat_number_is_real = Faraday.get(vies_url)
        end
      RUBY
      expect(scenario(code)).to eq([ [ "http-in-transaction", "the `validate :vat_number_is_real` validation" ] ])
    end

    it "flags a validation written as a block" do
      code = <<~RUBY
        class Order < ApplicationRecord
          validate do
            errors.add(:base, :unreachable) unless Faraday.get(url).success?
          end
        end
      RUBY
      expect(scenario(code)).to eq([ [ "http-in-transaction", "the `validate` validation block" ] ])
    end

    it "flags before_commit, which still runs inside the transaction" do
      code = <<~RUBY
        class Order < ApplicationRecord
          before_commit :sync
          def sync = Faraday.post(url)
        end
      RUBY
      expect(scenario(code)).to eq([ [ "http-in-transaction", "the `before_commit :sync` callback" ] ])
    end
  end

  describe "migrations" do
    it "flags work inside a migration, which runs in a DDL transaction" do
      code = <<~RUBY
        class BackfillGeocodes < ActiveRecord::Migration[8.0]
          def up
            Address.find_each { |address| address.update!(geo: Faraday.get(url(address)).body) }
          end
        end
      RUBY
      expect(scenario(code).map(&:first))
        .to contain_exactly("http-in-transaction", "iteration-in-transaction")
      expect(analyze(code).first.scope.label).to eq("`BackfillGeocodes#up`, which runs in a DDL transaction")
    end

    it "stays quiet when the migration opts out of the transaction" do
      code = <<~RUBY
        class BackfillGeocodes < ActiveRecord::Migration[8.0]
          disable_ddl_transaction!

          def up
            Address.find_each { |address| address.update!(geo: Faraday.get(url(address)).body) }
          end
        end
      RUBY
      expect(analyze(code)).to be_empty
    end
  end

  describe "blocking local work" do
    it "flags image processing in a callback" do
      code = <<~RUBY
        class Photo < ApplicationRecord
          after_save :build_thumb
          def build_thumb = ImageProcessing::Vips.source(file).resize_to_limit(200, 200).call
        end
      RUBY
      expect(scenario(code).map(&:first)).to eq([ "blocking-io-in-transaction" ])
    end

    it "flags csv parsing in a transaction" do
      code = <<~RUBY
        class Import
          def call
            ApplicationRecord.transaction { CSV.foreach(path) { |row| Order.create!(row) } }
          end
        end
      RUBY
      expect(scenario(code)).to eq([ [ "blocking-io-in-transaction", "the `ApplicationRecord.transaction` block" ] ])
    end

    it "ignores cheap path helpers" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def settle
            transaction { update!(receipt: File.join(root, "receipt.pdf")) }
          end
        end
      RUBY
      expect(analyze(code)).to be_empty
    end
  end

  describe "advisory locks" do
    it "flags work inside a with_advisory_lock block" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def settle
            Order.with_advisory_lock("settle") { Stripe::Refund.create(id) }
          end
        end
      RUBY
      expect(scenario(code)).to eq([ [ "external-service-in-transaction", "a `with_advisory_lock` block" ] ])
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
