# frozen_string_literal: true

require "io/console"

module Txray
  module Reporters
    class Live
      SPARKS = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █].freeze
      HIDE_CURSOR = "\e[?25l"
      SHOW_CURSOR = "\e[?25h"

      def initialize(path:, io: $stdout, threshold_ms: 250)
        @io = io
        @path = path
        @threshold_ms = threshold_ms
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
        header(monitor)
        stats(monitor)
        feed(monitor)
        hotspots(monitor)
        @io.print(dim("  ctrl-c to stop"))
        @io.flush
      end

      private

      def viewport
        rows, columns = IO.console&.winsize
        [ columns.to_i.positive? ? columns : 100, rows.to_i.positive? ? rows : 40 ]
      rescue StandardError
        [ 100, 40 ]
      end

      def feed_limit = (@height - 19).clamp(3, 9)

      def clip(text, budget)
        budget = [ budget, 12 ].max
        text.length <= budget ? text : "..#{text[-(budget - 2)..]}"
      end

      def header(monitor)
        @io.puts
        @io.puts "  #{bold(magenta("txray"))} #{dim("watching #{@path}")}#{" " * 2}#{dim(clock(monitor.uptime))}"
        @io.puts
      end

      def stats(monitor)
        if monitor.empty?
          @io.puts "  #{dim("waiting for the application to open a transaction")}"
          @io.puts
          return
        end

        @io.puts "  #{label("transactions")}#{count(monitor)}"
        @io.puts "  #{label("duration")}#{spread(monitor)}"
        @io.puts "  #{label("")}#{sparkline(monitor)}"
        @io.puts
      end

      def count(monitor)
        [ "#{monitor.transactions.size} seen",
          tint("#{monitor.slow} slow", monitor.slow.zero? ? :dim : :yellow),
          tint("#{monitor.flagged} with findings", monitor.flagged.zero? ? :dim : :red) ].join(dim("   "))
      end

      def spread(monitor)
        [ "p50 #{duration(monitor.percentile(0.5))}",
          "p95 #{duration(monitor.percentile(0.95))}",
          "max #{duration(monitor.durations.max.to_f)}" ].join(dim("   "))
      end

      def sparkline(monitor)
        values = monitor.durations.last(48)
        return dim("-") if values.empty?

        peak = [ values.max, 1.0 ].max
        values.map { |value| SPARKS[((value / peak) * (SPARKS.size - 1)).round] }.join
      end

      def feed(monitor)
        rows = monitor.recent(feed_limit)
        return if rows.empty?

        @io.puts "  #{dim("LIVE")}"
        rows.each { |event| @io.puts(event[:type] == "transaction" ? transaction_row(event) : violation_row(event)) }
        @io.puts
      end

      def transaction_row(event)
        marker = if event[:violations].to_a.any?
                   red("x")
                 else
                   (event[:duration_ms].to_f >= @threshold_ms ? yellow("!") : green("."))
                 end
        line = "  #{dim(time(event))} #{duration(event[:duration_ms]).rjust(18)}  #{marker}  " \
               "#{clip(source(event), @width - 36)}"
        [ line, *event[:violations].to_a.map { |violation| finding_row(violation) } ].join("\n")
      end

      def violation_row(event)
        "  #{dim(time(event))} #{elapsed(event[:duration_ms]).rjust(18)}  #{red("x")}  " \
          "#{red(event[:rule].to_s)} #{dim(clip(source(event), @width - 36 - event[:rule].to_s.length))}"
      end

      def elapsed(milliseconds) = milliseconds ? duration(milliseconds) : dim("-")

      def finding_row(violation)
        detail = [ violation[:message], duration_suffix(violation) ].compact.join(" ")
        rule = violation[:rule].to_s
        "  #{" " * 24}#{dim("|")} #{yellow(rule)} #{dim(clip(detail, @width - 28 - rule.length))}"
      end

      def duration_suffix(violation)
        "(#{duration(violation[:duration_ms])})" if violation[:duration_ms]
      end

      def source(event) = event[:source].to_s.sub(/:in\s+[`'"](.+)[`'"]\z/, " \\1")

      def hotspots(monitor)
        rows = monitor.hotspots(5)
        return if rows.empty?

        @io.puts "  #{dim("HOTSPOTS")}"
        rows.each do |entry|
          @io.puts "  #{"#{entry[:count]}x".rjust(4)}  #{yellow(entry[:rule].to_s.ljust(32))} " \
                   "#{dim(clip(source(entry), @width - 42))}"
        end
        @io.puts
      end

      def summary(monitor)
        return @io.puts("  no transactions observed") if monitor.empty?

        @io.puts "  #{monitor.transactions.size} transactions, #{monitor.slow} slow, " \
                 "#{monitor.findings.size} findings over #{clock(monitor.uptime)}"
        monitor.hotspots(10).each do |entry|
          @io.puts "  #{"#{entry[:count]}x".rjust(4)}  #{entry[:rule].to_s.ljust(32)} #{source(entry)}"
        end
      end

      def duration(milliseconds)
        value = milliseconds.to_f
        return "#{value.round}ms" if value < 1000

        "#{(value / 1000).round(2)}s"
      end

      def time(event) = Time.at(event[:at].to_f).strftime("%H:%M:%S")

      def clock(seconds)
        format("%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
      end

      def label(text) = text.ljust(16)

      def tint(text, color) = color == :dim ? dim(text) : send(color, text)

      def bold(text) = "\e[1m#{text}\e[0m"
      def dim(text) = "\e[2m#{text}\e[0m"
      def red(text) = "\e[31m#{text}\e[0m"
      def green(text) = "\e[32m#{text}\e[0m"
      def yellow(text) = "\e[33m#{text}\e[0m"
      def magenta(text) = "\e[35m#{text}\e[0m"
    end
  end
end
