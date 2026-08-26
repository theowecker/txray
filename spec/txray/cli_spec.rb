# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Txray::CLI do
  def run(*argv, code:)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "app", "models")
      FileUtils.mkdir_p(path)
      File.write(File.join(path, "order.rb"), code)
      io = StringIO.new
      status = described_class.start(argv + [ File.join(dir, "app") ], io: io)
      [ status, io.string ]
    end
  end

  let(:offending) do
    <<~RUBY
      class Order < ApplicationRecord
        after_create :charge
        def charge = Faraday.post(url)
      end
    RUBY
  end

  let(:clean) do
    <<~RUBY
      class Order < ApplicationRecord
        after_commit :charge, on: :create
        def charge = Faraday.post(url)
      end
    RUBY
  end

  it "exits cleanly when nothing is found" do
    status, output = run(code: clean)
    expect(status).to eq(described_class::EXIT_CLEAN)
    expect(output).to include("0 offenses")
  end

  it "exits non zero when offenses are found" do
    status, output = run(code: offending)
    expect(status).to eq(described_class::EXIT_OFFENSES)
    expect(output).to include("http-in-transaction")
  end

  it "honours the fail level" do
    status, = run("--fail-level", "high", code: offending)
    expect(status).to eq(described_class::EXIT_OFFENSES)
  end

  it "emits json" do
    _, output = run("--format", "json", code: offending)
    payload = JSON.parse(output)
    expect(payload.dig("offenses", 0, "rule")).to eq("http-in-transaction")
    expect(payload.dig("summary", "offenses")).to eq(1)
  end

  it "emits sarif" do
    _, output = run("--format", "sarif", code: offending)
    expect(JSON.parse(output).dig("runs", 0, "results", 0, "ruleId")).to eq("http-in-transaction")
  end

  it "emits github annotations" do
    _, output = run("--format", "github", code: offending)
    expect(output).to start_with("::error file=")
  end

  it "rejects unknown formats" do
    status, output = run("--format", "xml", code: offending)
    expect(status).to eq(described_class::EXIT_ERROR)
    expect(output).to include("unknown format")
  end

  it "filters with --except" do
    status, = run("--except", "http-in-transaction", code: offending)
    expect(status).to eq(described_class::EXIT_CLEAN)
  end
end
