# frozen_string_literal: true

module Txray
  module Reporters
    class Github
      LEVELS = { high: "error", medium: "warning", low: "notice" }.freeze

      def initialize(io: $stdout)
        @io = io
      end

      def report(result)
        result.offenses.each do |offense|
          level = LEVELS.fetch(offense.severity, "warning")
          title = "txray: #{offense.id}"
          @io.puts "::#{level} file=#{offense.path},line=#{offense.line},col=#{offense.column},title=#{title}::#{offense.message}"
        end
      end
    end
  end
end
