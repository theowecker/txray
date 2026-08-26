# frozen_string_literal: true

require "tmpdir"

RSpec.describe Txray::Scanner do
  it "resolves callbacks against concerns defined in another file" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app", "models", "concerns"))
      File.write(File.join(dir, "app", "models", "concerns", "chargeable.rb"), <<~RUBY)
        module Chargeable
          def charge
            Stripe::Charge.create(amount: total)
          end
        end
      RUBY
      File.write(File.join(dir, "app", "models", "order.rb"), <<~RUBY)
        class Order < ApplicationRecord
          include Chargeable
          after_create :charge
        end
      RUBY

      result = described_class.new(Txray::Config.new, paths: [ File.join(dir, "app") ]).run
      expect(result.offenses.map(&:id)).to eq([ "external-service-in-transaction" ])
      expect(result.offenses.first.path).to end_with("chargeable.rb")
      expect(result.files.size).to eq(2)
    end
  end

  it "reports a call reached from two transactions once" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "composer.rb"), <<~RUBY)
        class Composer
          def replace!
            Workout.transaction { persist }
          end

          def persist
            @workout.transaction do
              specs.each { |spec| Step.create!(spec) }
            end
          end
        end
      RUBY

      offenses = described_class.new(Txray::Config.new, paths: [ dir ]).run.offenses
      expect(offenses.map(&:id)).to eq([ "iteration-in-transaction" ])
      expect(offenses.first.trace).to be_empty
    end
  end

  it "skips excluded directories" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "spec", "order_spec.rb"), "class Order; after_create(:x); def x = Faraday.get(u); end")
      config = Txray::Config.new("include" => [ dir ])
      expect(described_class.new(config).run.files).to be_empty
    end
  end

  it "matches exclusions below the scanned root, not against the whole path" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, "tmp", "vendor", "app")
      FileUtils.mkdir_p(root)
      File.write(File.join(root, "order.rb"), <<~RUBY)
        class Order < ApplicationRecord
          after_create :charge
          def charge = Faraday.post(url)
        end
      RUBY

      result = described_class.new(Txray::Config.new, paths: [ root ]).run
      expect(result.offenses.map(&:id)).to eq([ "http-in-transaction" ])
    end
  end

  it "ignores files it cannot parse" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "broken.rb"), "class Order def")
      expect(described_class.new(Txray::Config.new, paths: [ dir ]).run.offenses).to be_empty
    end
  end
end
