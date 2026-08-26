# frozen_string_literal: true

module Txray
  Frame = Struct.new(:label, :path, :line, keyword_init: true) do
    def to_s = "#{label} (#{path}:#{line})"
  end

  class Offense
    SEVERITIES = %i[low medium high].freeze

    attr_reader :rule, :path, :line, :column, :snippet, :scope, :trace

    def initialize(rule:, path:, line:, column:, snippet:, scope:, trace: [])
      @rule = rule
      @path = path
      @line = line
      @column = column
      @snippet = snippet
      @scope = scope
      @trace = trace
    end

    def id = rule.id
    def severity = rule.severity
    def severity_rank = SEVERITIES.index(severity) || 0
    def location = "#{path}:#{line}:#{column}"
    def message = format(rule.message, snippet: snippet, scope: scope.label)

    def key = [ rule.id, path, line, column ]

    def sort_key = [ -severity_rank, path, line, column ]

    def to_h
      {
        rule: rule.id,
        severity: severity,
        category: rule.category,
        path: path,
        line: line,
        column: column,
        message: message,
        snippet: snippet,
        scope: { kind: scope.kind, label: scope.label, path: scope.path, line: scope.line },
        trace: trace.map { |frame| { label: frame.label, path: frame.path, line: frame.line } },
        remedy: rule.remedy
      }
    end
  end
end
