# frozen_string_literal: true

module Txray
  module Reporters
    class Github
      LEVELS = { high: "error", medium: "warning", low: "notice" }.freeze
      SUMMARY_LIMIT = 50

      def initialize(io: $stdout, summary_path: ENV.fetch("GITHUB_STEP_SUMMARY", nil))
        @io = io
        @summary_path = summary_path
      end

      def report(result)
        result.offenses.each { |offense| @io.puts annotation(offense) }
        write_summary(result)
      end

      private

      def annotation(offense)
        level = LEVELS.fetch(offense.severity, "warning")
        properties = [ "file=#{property(offense.path)}", "line=#{offense.line}", "col=#{offense.column}",
                       "title=#{property("txray #{offense.id}")}" ].join(",")
        "::#{level} #{properties}::#{message(offense)}"
      end

      def message(offense)
        body = [ offense.message, *offense.trace.map { |frame| "via #{frame}" }, offense.rule.remedy ].join("\n")
        escape(body)
      end

      def escape(text)
        text.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
      end

      def property(text)
        escape(text).gsub(":", "%3A").gsub(",", "%2C")
      end

      def write_summary(result)
        return if @summary_path.nil? || @summary_path.empty?

        File.open(@summary_path, "a") { |file| file.puts(summary(result)) }
      rescue StandardError
        nil
      end

      def summary(result)
        if result.offenses.empty?
          return [ "## txray", "",
                   "No slow work found inside transactions across #{result.files.size} files." ].join("\n")
        end

        [ "## txray", "", headline(result), "", table(result), footnote(result) ].compact.join("\n")
      end

      def headline(result)
        counts = Offense::SEVERITIES.reverse.filter_map do |severity|
          "#{result.counts[severity]} #{severity}" if result.counts[severity]
        end
        "**#{result.offenses.size} offenses** across #{result.files.size} files (#{counts.join(", ")})."
      end

      def table(result)
        rows = result.offenses.first(SUMMARY_LIMIT).map do |offense|
          "| #{offense.severity} | `#{offense.id}` | #{link(offense)} | #{cell(offense.message)} |"
        end
        [ "| Severity | Rule | Location | What happens |", "| --- | --- | --- | --- |", *rows ].join("\n")
      end

      def link(offense)
        "`#{offense.path}:#{offense.line}`"
      end

      def cell(text)
        text.to_s.gsub("|", "\\|").gsub("\n", " ")
      end

      def footnote(result)
        return nil if result.offenses.size <= SUMMARY_LIMIT

        "\n_Showing the first #{SUMMARY_LIMIT} of #{result.offenses.size}. Run `bundle exec txray` locally for the rest._"
      end
    end
  end
end
