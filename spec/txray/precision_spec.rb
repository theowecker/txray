# frozen_string_literal: true

require "tmpdir"

RSpec.describe "precision and reporting" do
  def scan(files, paths: nil)
    Dir.mktmpdir do |dir|
      files.each do |name, code|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, code)
      end
      Txray::Scanner.new(Txray::Config.new, paths: paths || [ dir ]).run
    end
  end

  it "keeps client tracking inside the file that built the client" do
    result = scan({
                    "gateway.rb" => <<~RUBY,
                      class Gateway
                        def call
                          client = Faraday.new(url: ENV["API"])
                          client.get("/x")
                        end
                      end
                    RUBY
                    "order.rb" => <<~RUBY
                      class Order < ApplicationRecord
                        def settle
                          client = Order.find(1)
                          transaction { client.update!(state: :done) }
                        end
                      end
                    RUBY
                  })

    expect(result.offenses.map { |offense| File.basename(offense.path) }).to be_empty
  end

  it "keeps instance variable tracking inside its own class" do
    code = <<~RUBY
      class Gateway
        def initialize = @client = Faraday.new(url: ENV["API"])
      end

      class Order < ApplicationRecord
        def initialize = @client = Order.new
        def settle
          transaction { @client.touch }
        end
      end
    RUBY
    expect(analyze(code)).to be_empty
  end

  it "does not treat a method as a client when it only builds one internally" do
    code = <<~RUBY
      class Order < ApplicationRecord
        def settle
          transaction { charge.amount }
        end

        def charge
          client = Faraday.new(url: ENV["API"])
          Payment.create!(body: client.get("/x").body)
        end
      end
    RUBY
    offenses = analyze(code)
    expect(offenses.map(&:line)).to eq([ 8 ])
    expect(offenses.first.snippet).to include("client.get")
  end

  it "still treats a memoized reader as a client" do
    code = <<~RUBY
      class Gateway
        def call
          ApplicationRecord.transaction { client.get("/x") }
        end

        def client = @client ||= Faraday.new(url: ENV["API"])
      end
    RUBY
    expect(analyze(code).map(&:id)).to eq([ "http-in-transaction" ])
  end

  it "does not resolve a class callback to an unrelated class elsewhere" do
    result = scan({
                    "mailer.rb" => "class ReportMailer\n  def notify = Faraday.post(\"/hook\")\nend\n",
                    "order.rb" => "class Order < ApplicationRecord\n  after_create :notify\nend\n"
                  })
    expect(result.offenses).to be_empty
  end

  it "still resolves a concern callback to the host class" do
    result = scan({
                    "syncable.rb" => <<~RUBY,
                      module Syncable
                        extend ActiveSupport::Concern
                        included { after_save :push_remote }
                      end
                    RUBY
                    "order.rb" => <<~RUBY
                      class Order < ApplicationRecord
                        include Syncable
                        def push_remote = Faraday.put(url)
                      end
                    RUBY
                  })
    expect(result.offenses.map(&:id)).to eq([ "http-in-transaction" ])
  end

  it "reports a path that does not exist" do
    expect { Txray::Scanner.new(Txray::Config.new, paths: [ "/does/not/exist" ]).run }
      .to raise_error(Txray::Error, /no such file or directory/)
  end

  it "reports a config file that does not exist" do
    expect { Txray::Config.load("/does/not/exist.yml") }
      .to raise_error(Txray::Error, /no such config file/)
  end

  it "lists files it could not parse instead of dropping them silently" do
    result = scan({ "broken.rb" => "class Order def", "fine.rb" => "class A; end" })
    expect(result.skipped.map { |path| File.basename(path) }).to eq([ "broken.rb" ])
    expect(result.files.map { |path| File.basename(path) }).to eq([ "fine.rb" ])
  end
end
