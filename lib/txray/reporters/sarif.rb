# frozen_string_literal: true

require "json"

module Txray
  module Reporters
    class Sarif
      LEVELS = { high: "error", medium: "warning", low: "note" }.freeze

      def initialize(io: $stdout)
        @io = io
      end

      def report(result)
        @io.puts JSON.pretty_generate(
          "$schema" => "https://json.schemastore.org/sarif-2.1.0.json",
          version: "2.1.0",
          runs: [ { tool: tool, results: result.offenses.map { |offense| sarif_result(offense) } } ]
        )
      end

      private

      def tool
        {
          driver: {
            name: "txray",
            version: Txray::VERSION,
            informationUri: "https://github.com/theowecker/txray",
            rules: Rules.all.values.map do |rule|
              { id: rule.id, shortDescription: { text: rule.id.tr("-", " ") }, fullDescription: { text: rule.remedy } }
            end
          }
        }
      end

      def sarif_result(offense)
        {
          ruleId: offense.id,
          level: LEVELS.fetch(offense.severity, "warning"),
          message: { text: "#{offense.message}. #{offense.rule.remedy}" },
          locations: [ {
            physicalLocation: {
              artifactLocation: { uri: offense.path },
              region: { startLine: offense.line, startColumn: offense.column }
            }
          } ]
        }
      end
    end
  end
end
