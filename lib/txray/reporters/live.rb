# frozen_string_literal: true

require "io/console"

module Txray
  module Reporters
    class Live
      SPARKS = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █].freeze
      SEVERITY_COLORS = { high: 91, medium: 93, low: 96 }.freeze
      HIDE_CURSOR = "\e[?25l"
      SHOW_CURSOR = "\e[?25h"

      def initialize(path:, io: $stdout, threshold_ms: 250, color: Reporters.color?(io))
        @io = io
        @path = path
        @threshold_ms = threshold_ms
        @color = color
        @width = 100
        @height = 40
      end

      def open = @io.print(HIDE_CURSOR)

      def close(monitor)
        @width, @height = viewport
        @io.print(SHOW_CURSOR)
        @io.puts
        summary(monitor)
      end

      def draw(monitor)
        @width, @height = viewport
        @io.print("\e[H\e[2J")
        title(monitor)
        meters(monitor)
        histogram(monitor)
        feed(monitor)
        hotspots(monitor)
        footer
        @io.flush
      end

      private

      def viewport
        rows, columns = IO.console&.winsize
        [ columns.to_i.positive? ? columns : 100, rows.to_i.positive? ? rows : 40 ]
      rescue StandardError
        [ 100, 40 ]
      end

      def title(monitor)
        workers = monitor.pids
        right = "up #{clock(monitor.uptime)}#{"  #{workers} pids" if workers > 1}"
        left = " txray  #{@path}"
        @io.puts bar(left, right)
        @io.puts
      end

      def meters(monitor)
        return setup_hint if monitor.transactions.empty?

        counts = monitor.breakdown
        summary = legend(monitor, counts)
        @io.puts "  #{label("txns")}#{stacked(counts, room(summary))}  #{summary}"
        spread = percentiles(monitor)
        @io.puts "  #{label("time")}#{sparkline(monitor, room(spread))}  #{spread}"
        @io.puts
      end

      def room(text) = (@width - 12 - visible(text)).clamp(8, 34)

      def setup_hint
        if File.exist?(@path)
          @io.puts "  #{dim("waiting for the application to open a transaction")}"
          return @io.puts
        end

        @io.puts "  #{paint("no event log yet", 93)} #{dim("at #{@path}")}"
        @io.puts
        @io.puts "  #{dim("the runtime guard writes it. to turn it on:")}"
        @io.puts
        @io.puts "    #{paint("1", 97)}  Gemfile      #{dim('gem "txray"   not require: false')}"
        @io.puts "    #{paint("2", 97)}  .txray.yml   #{dim("runtime:")}"
        @io.puts "                   #{dim("  enabled: true")}"
        @io.puts "    #{paint("3", 97)}  #{dim("restart the app, then exercise it")}"
        @io.puts
      end

      def stacked(counts, width)
        parts = [ [ counts[:ok], 92 ], [ counts[:slow], 93 ], [ counts[:flagged], 91 ] ]
        return "#{dim("[")}#{dim("·" * width)}#{dim("]")}" if parts.sum(&:first).zero?

        cells = allocate(parts.map(&:first), width)
        rendered = parts.each_with_index.map { |(_, color), i| paint("█" * cells[i], color) }.join
        "#{dim("[")}#{rendered}#{dim("]")}"
      end

      def allocate(counts, width)
        total = counts.sum
        cells = counts.map { |count| count.zero? ? 0 : [ ((count.to_f / total) * width).round, 1 ].max }
        cells[cells.index(cells.max)] += width - cells.sum
        cells.map { |cell| [ cell, 0 ].max }
      end

      def legend(monitor, counts)
        [ "#{monitor.transactions.size} txns",
          paint("#{counts[:ok]} ok", 92),
          paint("#{counts[:slow]} slow", 93),
          paint("#{counts[:flagged]} flagged", 91) ].join(dim(" · "))
      end

      def percentiles(monitor)
        [ tinted("p50", monitor.percentile(0.5)),
          tinted("p95", monitor.percentile(0.95)),
          tinted("max", monitor.durations.max.to_f) ].join(dim(" · "))
      end

      def tinted(name, value)
        "#{dim(name)} #{paint(duration(value), heat(value))}"
      end

      def heat(value)
        return 91 if value >= @threshold_ms
        return 93 if value >= @threshold_ms / 2.0

        92
      end

      def sparkline(monitor, width)
        values = monitor.durations.last(width)
        return dim("·" * width) if values.empty?

        scale = Math.log(1 + [ values.max, 1.0 ].max)
        values.map do |value|
          level = ((Math.log(1 + value) / scale) * (SPARKS.size - 1)).round
          paint(SPARKS[level.clamp(0, SPARKS.size - 1)], heat(value))
        end.join
      end

      def histogram(monitor)
        rows = monitor.histogram.reject { |row| row[:count].zero? }
        return if rows.empty?

        peak = rows.map { |row| row[:count] }.max
        width = @width < 72 ? [ @width - 20, 10 ].max : [ (@width - 30) / 2, 12 ].max
        columns = @width < 72 ? 1 : 2
        rows.each_slice(columns) { |group| @io.puts("  #{group.map { |row| bucket(row, peak, width) }.join("  ")}") }
        @io.puts
      end

      def bucket(row, peak, width)
        filled = [ ((row[:count].to_f / peak) * width).round, 1 ].max
        color = heat(row[:limit] == Float::INFINITY ? @threshold_ms * 10 : row[:limit] - 1)
        "#{dim(row[:label].rjust(7))} #{paint("█" * filled, color)}#{dim("·" * [ width - filled, 0 ].max)} " \
          "#{count_label(row[:count])}"
      end

      def count_label(count) = paint(count.to_s.ljust(4), 97)

      def feed(monitor)
        rows = monitor.recent(feed_limit)
        return if rows.empty?

        @io.puts bar("  TIME       ELAPSED   SOURCE", "")
        rows.each { |event| @io.puts(event[:type] == "transaction" ? transaction_row(event) : violation_row(event)) }
        @io.puts
      end

      def transaction_row(event)
        findings = event[:violations].to_a
        state = if findings.any?
                  paint("●", 91)
                elsif event[:duration_ms].to_f >= @threshold_ms
                  paint("●", 93)
                else
                  paint("·", 92)
                end
        elapsed = paint(duration(event[:duration_ms]).rjust(9), heat(event[:duration_ms].to_f))
        line = "  #{dim(time(event))} #{elapsed} #{state} #{clip(source(event), @width - 34)}"
        [ line, *findings.map { |finding| finding_row(finding) } ].join("\n")
      end

      def violation_row(event)
        rule = event[:rule].to_s
        "  #{dim(time(event))} #{dim("        -")} #{paint("●", severity_color(rule))} " \
          "#{paint(rule, severity_color(rule))} #{dim(clip(source(event), @width - 36 - rule.length))}"
      end

      def finding_row(finding)
        rule = finding[:rule].to_s
        detail = [ finding[:message], duration_suffix(finding) ].compact.join(" ")
        "  #{" " * 20}#{dim("└")} #{paint(rule, severity_color(rule))} " \
          "#{dim(clip(detail, @width - 26 - rule.length))}"
      end

      def severity_color(rule)
        SEVERITY_COLORS.fetch(Rules.all[rule]&.severity, 95)
      end

      def duration_suffix(finding)
        "(#{duration(finding[:duration_ms])})" if finding[:duration_ms]
      end

      def hotspots(monitor)
        rows = monitor.hotspots(hotspot_limit)
        return if rows.empty?

        @io.puts bar("  HOTSPOTS", "")
        rows.each do |entry|
          rule = entry[:rule].to_s
          @io.puts "  #{paint("#{entry[:count]}x".rjust(5), 97)}  #{paint(rule.ljust(32), severity_color(rule))} " \
                   "#{dim(clip(source(entry), @width - 45))}"
        end
        @io.puts
      end

      def footer = @io.print(bar("  ctrl-c  stop", ""))

      def summary(monitor)
        return @io.puts("  no transactions observed") if monitor.empty?

        counts = monitor.breakdown
        @io.puts "  #{monitor.transactions.size} transactions over #{clock(monitor.uptime)}: " \
                 "#{counts[:ok]} ok, #{counts[:slow]} slow, #{counts[:flagged]} with findings"
        monitor.hotspots(10).each do |entry|
          @io.puts "  #{"#{entry[:count]}x".rjust(5)}  #{entry[:rule].to_s.ljust(32)} #{source(entry)}"
        end
      end

      def bar(left, right)
        padding = [ @width - visible(left) - visible(right) - 1, 1 ].max
        return "#{left}#{" " * padding}#{right} " unless @color

        "\e[7m#{left}#{" " * padding}#{right} \e[0m"
      end

      def feed_limit = (@height - 22).clamp(3, 10)
      def hotspot_limit = (@height - 30).clamp(2, 5)

      def clip(text, budget)
        budget = [ budget, 12 ].max
        text.length <= budget ? text : "..#{text[-(budget - 2)..]}"
      end

      def visible(text) = text.gsub(/\e\[[0-9;?]*[a-zA-Z]/, "").length

      def duration(milliseconds)
        value = milliseconds.to_f
        return "#{value.round}ms" if value < 1000

        "#{(value / 1000).round(2)}s"
      end

      def time(event) = Time.at(event[:at].to_f).strftime("%H:%M:%S")
      def source(event) = event[:source].to_s.sub(/:in\s+[`'"](.+)[`'"]\z/, " \\1")
      def label(text) = dim(text.ljust(6))

      def clock(seconds)
        format("%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
      end

      def paint(text, color) = @color ? "\e[#{color}m#{text}\e[0m" : text
      def dim(text) = @color ? "\e[2m#{text}\e[0m" : text
    end
  end
end
