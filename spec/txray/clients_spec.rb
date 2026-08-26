# frozen_string_literal: true

RSpec.describe "client and dispatch resolution" do
  def rules(code) = analyze(code).map(&:id)

  describe "clients held in variables" do
    it "flags a request on a client in a local variable" do
      code = <<~RUBY
        class Order < ApplicationRecord
          after_create :charge
          def charge
            client = Faraday.new(url: ENV["API"])
            client.post("/charges", payload)
          end
        end
      RUBY
      offenses = analyze(code)
      expect(offenses.map(&:id)).to eq([ "http-in-transaction" ])
      expect(offenses.first.snippet).to eq('client.post("/charges", payload)')
    end

    it "flags a request on a client in an instance variable" do
      code = <<~RUBY
        class Gateway
          def initialize = @http = Faraday.new(url: ENV["API"])
          def call(order)
            ApplicationRecord.transaction { @http.post("/charges", order.to_json) }
          end
        end
      RUBY
      expect(rules(code)).to eq([ "http-in-transaction" ])
    end

    it "flags a request on a memoized client method" do
      code = <<~RUBY
        class Gateway
          def charge(order)
            ApplicationRecord.transaction { client.post("/charges", order.to_json) }
          end
          def client = @client ||= Faraday.new(url: ENV["API"])
        end
      RUBY
      expect(rules(code)).to eq([ "http-in-transaction" ])
    end

    it "flags a request on a client held in a constant" do
      code = <<~RUBY
        class Gateway
          CLIENT = Faraday.new(url: ENV["API"])
          def charge
            ApplicationRecord.transaction { CLIENT.post("/charges") }
          end
        end
      RUBY
      expect(rules(code)).to eq([ "http-in-transaction" ])
    end

    it "flags a call through a delegated client" do
      code = <<~RUBY
        class Order < ApplicationRecord
          delegate :charge, to: :gateway
          def gateway = Stripe::StripeClient.new(key)
          def settle
            transaction { charge(total) }
          end
        end
      RUBY
      expect(rules(code)).to eq([ "external-service-in-transaction" ])
    end

    it "reports a chained client call once, at the outermost call" do
      code = <<~RUBY
        class Order < ApplicationRecord
          def notify
            transaction { Twilio::REST::Client.new(sid, token).messages.create(to: phone) }
          end
        end
      RUBY
      offenses = analyze(code)
      expect(offenses.size).to eq(1)
      expect(offenses.first.snippet).to include("messages.create")
    end

    it "does not report building a client as a request" do
      code = <<~RUBY
        class Gateway
          def call
            ApplicationRecord.transaction { Order.create!(client: Faraday.new(url: ENV["API"])) }
          end
        end
      RUBY
      expect(analyze(code)).to be_empty
    end

    it "recognises configured clients as taint sources" do
      code = <<~RUBY
        class Gateway
          def call
            ledger = InternalApi::Ledger.new(key)
            ApplicationRecord.transaction { ledger.post(entry) }
          end
        end
      RUBY
      config = Txray::Config.new("external_clients" => [ "InternalApi" ])
      expect(analyze(code, config: config).map(&:id)).to eq([ "external-service-in-transaction" ])
    end
  end

  describe "metaprogramming" do
    it "resolves send with a symbol literal" do
      code = <<~RUBY
        class Order < ApplicationRecord
          after_create :dispatch
          def dispatch = send(:charge)
          def charge = Stripe::Charge.create(amount: total)
        end
      RUBY
      expect(rules(code)).to eq([ "external-service-in-transaction" ])
    end

    it "indexes methods built with define_method" do
      code = <<~RUBY
        class Order < ApplicationRecord
          after_create :charge
          define_method(:charge) { Stripe::Charge.create(amount: total) }
        end
      RUBY
      expect(rules(code)).to eq([ "external-service-in-transaction" ])
    end

    it "reports dispatch it cannot resolve as a blind spot" do
      code = <<~RUBY
        class Order < ApplicationRecord
          after_create :dispatch
          def dispatch = send("\#{provider}_charge")
        end
      RUBY
      offenses = analyze(code)
      expect(offenses.map(&:id)).to eq([ "dynamic-dispatch-in-transaction" ])
      expect(offenses.first.severity).to eq(:low)
    end

    it "stays quiet on dispatch it can resolve to something harmless" do
      code = <<~RUBY
        class Order < ApplicationRecord
          after_create :dispatch
          def dispatch = public_send(:touch)
        end
      RUBY
      expect(analyze(code)).to be_empty
    end
  end

  describe "newly catalogued services" do
    {
      "HTTP.post(url, json: payload)" => "http-in-transaction",
      "Savon.client(wsdl: wsdl).call(:submit)" => "http-in-transaction",
      "Net::SMTP.start(host)" => "http-in-transaction",
      "Geocoder.search(address)" => "external-service-in-transaction",
      "geocode" => "external-service-in-transaction",
      "Product.reindex" => "external-service-in-transaction",
      "LaunchDarkly::LDClient.new(key).variation(flag, user, false)" => "external-service-in-transaction",
      "broadcast_replace_to(album)" => "broadcast-in-transaction",
      'ActionCable.server.broadcast("orders", payload)' => "broadcast-in-transaction"
    }.each do |call, rule|
      it "flags #{call} as #{rule}" do
        code = <<~RUBY
          class Order < ApplicationRecord
            def settle
              transaction { #{call} }
            end
          end
        RUBY
        expect(rules(code)).to eq([ rule ])
      end
    end
  end
end
