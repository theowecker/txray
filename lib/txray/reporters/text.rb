# frozen_string_literal: true

module Txray
  module Reporters
    class Text
      COLORS = { high: 31, medium: 33, low: 36 }.freeze

      def initialize(io: $stdout, color: io.tty?)
        @io = io
        @color = color
      end

      def report(result)
        result.offenses.group_by(&:path).each do |path, offenses|
          @io.puts bold(path)
          offenses.each { |offense| print_offense(offense) }
          @io.puts
        end
        print_summary(result)
      end

      private

      def print_offense(offense)
        @io.puts "  #{offense.line}:#{offense.column}  #{tint(offense.severity.to_s.ljust(6), offense.severity)} #{offense.id}"
        @io.puts "    #{offense.message}"
        offense.trace.each { |frame| @io.puts dim("      via #{frame}") }
        @io.puts dim("    #{offense.rule.remedy}")
      end

      def print_summary(result)
        counts = result.counts
        summary = Offense::SEVERITIES.reverse.filter_map { |s| "#{counts[s]} #{s}" if counts[s] }
        @io.puts "#{result.files.size} files scanned, #{result.offenses.size} offenses" \
                 "#{" (#{summary.join(", ")})" unless summary.empty?}"
        return if result.skipped.to_a.empty?

        @io.puts dim("#{result.skipped.size} files could not be parsed and were skipped:")
        result.skipped.each { |path| @io.puts dim("  #{path}") }
      end

      def tint(text, severity) = @color ? "\e[#{COLORS.fetch(severity, 0)}m#{text}\e[0m" : text
      def bold(text) = @color ? "\e[1m#{text}\e[0m" : text
      def dim(text) = @color ? "\e[2m#{text}\e[0m" : text
    end
  end
end
