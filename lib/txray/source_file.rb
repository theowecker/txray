# frozen_string_literal: true

module Txray
  class SourceFile
    DIRECTIVE = /#\s*txray:disable(?<rules>[\w,\s-]*)/

    attr_reader :path, :root

    def self.parse(path, code: nil)
      code ||= File.read(path)
      result = Prism.parse(code)
      return nil if result.failure?

      new(path: path, root: result.value, comments: result.comments)
    rescue StandardError
      nil
    end

    def initialize(path:, root:, comments: [])
      @path = path
      @root = root
      @directives = build_directives(comments)
    end

    def disabled?(line, rule_id)
      rules = @directives[line] || @directives[line - 1]
      return false if rules.nil?

      rules.empty? || rules.include?(rule_id)
    end

    private

    def build_directives(comments)
      comments.each_with_object({}) do |comment, directives|
        match = DIRECTIVE.match(comment.slice)
        next unless match

        directives[comment.location.start_line] = match[:rules].to_s.split(/[,\s]+/).reject(&:empty?)
      end
    end
  end
end
