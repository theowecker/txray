# frozen_string_literal: true

require "active_record"
require "active_job"
require "tmpdir"

RSpec.describe Txray::Runtime do
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define do
      create_table(:orders, force: true) { |t| t.string :state }
    end
    Object.const_set(:TxrayOrder, Class.new(ActiveRecord::Base) { self.table_name = "orders" }) unless defined?(TxrayOrder)
  end

  before do
    described_class.uninstall
    @log = File.join(Dir.mktmpdir, "txray.ndjson")
    described_class.install(threshold_ms: 40, log_path: @log, guard_http: false, logger: Logger.new(IO::NULL))
  end

  def events = File.readlines(@log).map { |line| JSON.parse(line, symbolize_names: true) }

  it "knows when a transaction is open" do
    expect(described_class.transaction_open?).to be(false)
    ActiveRecord::Base.transaction { expect(described_class.transaction_open?).to be(true) }
  end

  it "records a transaction that runs past the threshold" do
    ActiveRecord::Base.transaction do
      TxrayOrder.create!(state: "new")
      sleep 0.06
    end

    transaction = events.find { |event| event[:type] == "transaction" }
    expect(transaction[:duration_ms]).to be >= 40
    expect(transaction[:outcome]).to eq("commit")
    expect(transaction[:source]).to include("runtime_spec.rb")
  end

  it "stays quiet for fast transactions" do
    ActiveRecord::Base.transaction { TxrayOrder.create!(state: "new") }
    expect(File.exist?(@log)).to be(false)
  end

  it "records a rolled back transaction under its own outcome" do
    ActiveRecord::Base.transaction do
      TxrayOrder.create!(state: "new")
      sleep 0.06
      raise ActiveRecord::Rollback
    end

    expect(events.find { |event| event[:type] == "transaction" }[:outcome]).to eq("rollback")
  end

  it "attributes a violation to the transaction that was open" do
    ActiveRecord::Base.transaction do
      TxrayOrder.create!(state: "new")
      described_class.violation("http-in-transaction", "POST api.example.com", duration_ms: 12.0)
    end

    transaction = events.find { |event| event[:type] == "transaction" }
    expect(transaction[:violations].map { |violation| violation[:rule] }).to eq([ "http-in-transaction" ])
    expect(transaction[:violations].first[:duration_ms]).to eq(12.0)
  end

  it "raises when configured to" do
    described_class.uninstall
    described_class.install(threshold_ms: 40, log_path: @log, on_violation: :raise, guard_http: false,
                            logger: Logger.new(IO::NULL))

    expect { described_class.violation("http-in-transaction", "POST api.example.com") }
      .to raise_error(described_class::Violation, /http-in-transaction/)
  end

  it "suppresses violations inside an ignore block" do
    described_class.ignore { described_class.violation("http-in-transaction", "POST api.example.com") }
    expect(File.exist?(@log)).to be(false)
  end

  it "suppresses violations matching an ignore pattern" do
    described_class.uninstall
    described_class.install(threshold_ms: 40, log_path: @log, ignore: [ "legacy_sync" ],
                            guard_http: false, logger: Logger.new(IO::NULL))

    described_class.violation("http-in-transaction", "POST legacy_sync.example.com")
    expect(File.exist?(@log)).to be(false)
  end

  it "does not install twice" do
    expect(described_class.install(threshold_ms: 999)).to be_nil
    expect(described_class.options[:threshold_ms]).to eq(40)
  end
end
