# frozen_string_literal: true

module Txray
  class Tail
    INTERVAL = 0.15

    def initialize(path, from_start: false)
      @path = path
      @skip_existing = !from_start && File.exist?(path)
    end

    def each_batch
      loop do
        yield read
        sleep INTERVAL
      end
    end

    private

    def read
      return [] unless File.exist?(@path)

      reopen if @file.nil? || rotated?
      @file.read.to_s.lines.map(&:chomp).reject(&:empty?)
    rescue StandardError
      []
    end

    def rotated?
      return true unless File.identical?(@path, @file)

      File.size(@path) < @file.pos
    end

    def reopen
      @file&.close
      @file = File.open(@path, "r")
      @file.seek(0, IO::SEEK_END) if @skip_existing
      @skip_existing = false
    end
  end
end
