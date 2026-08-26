# frozen_string_literal: true

require "io/console"

module Txray
  module Reporters
    class Text
      COLORS = { high: 91, medium: 93, low: 96 }.freeze

      def initialize(io: $stdout, color: Reporters.color?(io))
        @io = io
        @color = color
        @width = width
      end

      def report(result)
        result.offenses.group_by(&:path).each_with_index do |(path, offenses), index|
          @io.puts if index.positive?
          heading(path, offenses)
          offenses.each_with_index do |offense, position|
            @io.puts if position.positive?
            offense_body(offense)
          end
        end

        @io.puts
        summary(result)
      end

      private

      def heading(path, offenses)
        count = "#{offenses.size} #{offenses.size == 1 ? "offense" : "offenses"}"
        leader = "·" * [ @width - path.length - count.length - 2, 3 ].max
        @io.puts "#{bold(path)} #{dim(leader)} #{dim(count)}"
      end

      def offense_body(offense)
        @io.puts "  #{location(offense)}  #{tint(offense.severity.to_s.ljust(6), offense.severity)}  " \
                 "#{tint(offense.id, offense.severity)}"
        paragraph(offense.message, "      ", 6).each { |line| @io.puts line }
        offense.trace.each { |frame| @io.puts dim("      └ via #{frame}") }
        paragraph(offense.rule.remedy, "      → ", 8).each { |line| @io.puts dim(line) }
      end

      def paragraph(text, prefix, indent)
        lines = fold(text, [ @width - indent, 24 ].max)
        [ "#{prefix}#{lines.first}", *lines.drop(1).map { |line| "#{" " * indent}#{line}" } ]
      end

      def fold(text, budget)
        text.split.each_with_object([ "" ]) do |word, lines|
          if lines.last.empty?
            lines[-1] = word
          elsif lines.last.length + 1 + word.length <= budget
            lines[-1] = "#{lines.last} #{word}"
          else
            lines << word
          end
        end
      end

      def location(offense) = "#{offense.line}:#{offense.column}".ljust(7)

      def summary(result)
        counts = result.counts
        parts = [ "#{result.files.size} files scanned", "#{result.offenses.size} offenses" ]
        parts += Offense::SEVERITIES.reverse.filter_map do |severity|
          tint("#{counts[severity]} #{severity}", severity) if counts[severity]
        end

        @io.puts dim("─" * @width)
        @io.puts parts.join(dim(" · "))
        skipped(result)
      end

      def skipped(result)
        return if result.skipped.to_a.empty?

        @io.puts dim("#{result.skipped.size} files could not be parsed and were skipped:")
        result.skipped.each { |path| @io.puts dim("  #{path}") }
      end

      def width
        columns = IO.console&.winsize&.last
        (columns.to_i.positive? ? columns : 88).clamp(40, 100)
      rescue StandardError
        88
      end

      def tint(text, severity) = @color ? "\e[#{COLORS.fetch(severity, 0)}m#{text}\e[0m" : text
      def bold(text) = @color ? "\e[1m#{text}\e[0m" : text
      def dim(text) = @color ? "\e[2m#{text}\e[0m" : text
    end
  end
end
