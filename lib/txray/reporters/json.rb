# frozen_string_literal: true

require "json"

module Txray
  module Reporters
    class Json
      def initialize(io: $stdout)
        @io = io
      end

      def report(result)
        @io.puts JSON.pretty_generate(
          version: Txray::VERSION,
          summary: { files: result.files.size, offenses: result.offenses.size, severities: result.counts,
                     skipped: result.skipped.to_a },
          offenses: result.offenses.map(&:to_h)
        )
      end
    end
  end
end
