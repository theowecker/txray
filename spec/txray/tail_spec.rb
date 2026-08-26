# frozen_string_literal: true

require "tmpdir"

RSpec.describe Txray::Tail do
  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, "events.ndjson")
      example.run
    end
  end

  def collect(tail, count, timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    lines = []
    tail.each_batch do |batch|
      lines.concat(batch)
      break if lines.size >= count || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end
    lines
  end

  it "waits for a file that does not exist yet" do
    tail = described_class.new(@path)
    Thread.new do
      sleep 0.2
      File.write(@path, "one\n")
    end
    expect(collect(tail, 1)).to eq([ "one" ])
  end

  it "reads only what is appended after it starts" do
    File.write(@path, "old\n")
    tail = described_class.new(@path)
    collect_thread = Thread.new { collect(tail, 1) }
    sleep 0.3
    File.write(@path, "new\n", mode: "a")

    expect(collect_thread.value).to eq([ "new" ])
  end

  it "replays existing content when asked" do
    File.write(@path, "old\n")
    expect(collect(described_class.new(@path, from_start: true), 1)).to eq([ "old" ])
  end

  it "recovers when the log is rotated away" do
    File.write(@path, "one\n")
    tail = described_class.new(@path, from_start: true)
    collect(tail, 1)

    File.delete(@path)
    File.write(@path, "fresh\n")
    expect(collect(tail, 1)).to eq([ "fresh" ])
  end

  it "skips blank lines" do
    tail = described_class.new(@path, from_start: true)
    File.write(@path, "\n\nreal\n")
    expect(collect(tail, 1)).to eq([ "real" ])
  end
end
