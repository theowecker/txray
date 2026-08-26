# frozen_string_literal: true

module Txray
  class WatchCommand
    def initialize(path:, threshold_ms:, io: $stdout, from_start: false)
      @path = path
      @io = io
      @monitor = Monitor.new(threshold_ms: threshold_ms)
      @tail = Tail.new(path, from_start: from_start)
      @view = Reporters::Live.new(io: io, path: path, threshold_ms: threshold_ms)
    end

    def run
      return stream unless @io.tty?

      @view.open
      @view.draw(@monitor)
      @tail.each_batch do |lines|
        next if lines.empty?

        lines.each { |line| @monitor.absorb(line) }
        @view.draw(@monitor)
      end
    rescue Interrupt
      nil
    ensure
      @view.close(@monitor) if @io.tty?
    end

    private

    def stream
      @tail.each_batch do |lines|
        lines.each do |line|
          event = @monitor.absorb(line)
          @io.puts(JSON.generate(event)) if event
        end
      end
    rescue Interrupt
      nil
    end
  end
end
