# frozen_string_literal: true

module Txray
  class SourceFile
    DIRECTIVE = /\A#\s*txray:(?<action>disable|enable)\b(?<rules>[\w,\s-]*)/

    attr_reader :path, :root

    def self.parse(path, code: nil)
      code ||= File.read(path)
      result = Prism.parse(code)
      return nil if result.failure?

      new(path: path, root: result.value, comments: result.comments, code: code)
    rescue StandardError
      nil
    end

    def initialize(path:, root:, comments: [], code: "")
      @path = path
      @root = root
      @lines = code.lines
      @inline = {}
      @regions = []
      index(comments)
    end

    def disabled?(line, rule_id)
      return true if covers?(@inline[line], rule_id)

      @regions.any? { |region| line.between?(region[:from], region[:to]) && covers?(region[:rules], rule_id) }
    end

    private

    def covers?(rules, rule_id)
      return false if rules.nil?

      rules.empty? || rules.include?(rule_id)
    end

    def index(comments)
      open = {}

      comments.each do |comment|
        match = DIRECTIVE.match(comment.slice.to_s.strip)
        next unless match

        apply(match, comment, open)
      end

      open.each { |key, from| @regions << region(key, from, Float::INFINITY) }
    end

    def apply(match, comment, open)
      rules = named_rules(match[:rules])
      line = comment.location.start_line

      if trailing?(comment)
        @inline[line] = rules if match[:action] == "disable"
      elsif match[:action] == "disable"
        (rules.empty? ? [ :all ] : rules).each { |key| open[key] ||= line }
      else
        close(open, rules, line)
      end
    end

    def close(open, rules, line)
      keys = rules.empty? ? open.keys.dup : rules
      keys.each do |key|
        from = open.delete(key)
        @regions << region(key, from, line) if from
      end
    end

    def region(key, from, to)
      { from: from, to: to, rules: key == :all ? [] : [ key ] }
    end

    def named_rules(text)
      text.to_s.split(/[,\s]+/).reject { |rule| rule.empty? || rule == "all" }
    end

    def trailing?(comment)
      prefix = @lines[comment.location.start_line - 1].to_s[0, comment.location.start_column].to_s
      !prefix.strip.empty?
    end
  end
end
