# frozen_string_literal: true

RSpec.describe Txray::Monitor do
  subject(:monitor) { described_class.new(threshold_ms: 100) }

  def transaction(duration, violations: [], source: "app/models/order.rb:3")
    JSON.generate(type: "transaction", at: Time.now.to_f, pid: 1, duration_ms: duration,
                  outcome: "commit", source: source, violations: violations)
  end

  it "ignores lines it cannot parse" do
    expect(monitor.absorb("not json")).to be_nil
    expect(monitor).to be_empty
  end

  it "ignores events of an unknown type" do
    expect(monitor.absorb(JSON.generate(type: "heartbeat"))).to be_nil
    expect(monitor).to be_empty
  end

  it "counts slow transactions against the threshold" do
    monitor.absorb(transaction(40))
    monitor.absorb(transaction(140))
    expect(monitor.slow).to eq(1)
    expect(monitor.transactions.size).to eq(2)
  end

  it "counts transactions carrying findings" do
    monitor.absorb(transaction(10, violations: [ { rule: "http-in-transaction", source: "a.rb:1" } ]))
    expect(monitor.flagged).to eq(1)
  end

  it "computes percentiles over observed durations" do
    [ 10, 20, 30, 40, 1000 ].each { |value| monitor.absorb(transaction(value)) }
    expect(monitor.percentile(0.5)).to eq(30)
    expect(monitor.percentile(0.95)).to eq(1000)
  end

  it "returns zero percentiles with nothing recorded" do
    expect(monitor.percentile(0.5)).to eq(0.0)
  end

  it "ranks hotspots across nested findings and slow transactions" do
    2.times { monitor.absorb(transaction(10, violations: [ { rule: "http-in-transaction", source: "a.rb:1" } ])) }
    monitor.absorb(transaction(500, source: "b.rb:2"))

    expect(monitor.hotspots(5)).to eq([
                                        { rule: "http-in-transaction", source: "a.rb:1", count: 2 },
                                        { rule: "slow-transaction", source: "b.rb:2", count: 1 }
                                      ])
  end

  it "keeps only the most recent events in the feed" do
    60.times { monitor.absorb(transaction(10)) }
    expect(monitor.recent(100).size).to eq(40)
  end
end
