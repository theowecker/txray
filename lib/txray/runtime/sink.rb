# frozen_string_literal: true

require "json"

module Txray
  module Runtime
    class Sink
      def self.build(path)
        path ? new(path) : Null.new
      end

      def initialize(path)
        @path = path
      end

      def write(event)
        prepare
        File.open(@path, "a") do |file|
          file.flock(File::LOCK_EX)
          file.puts(JSON.generate(event))
        end
      rescue StandardError
        nil
      end

      private

      def prepare
        return if @prepared

        FileUtils.mkdir_p(File.dirname(@path))
        @prepared = true
      end

      class Null
        def write(_event) = nil
      end
    end
  end
end
