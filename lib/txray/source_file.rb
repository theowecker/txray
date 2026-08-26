# frozen_string_literal: true

module Txray
  class SourceFile
    attr_reader :path, :root

    def self.parse(path, code: nil)
      code ||= File.read(path)
      result = Prism.parse(code)
      return nil if result.failure?

      new(path: path, root: result.value)
    rescue StandardError
      nil
    end

    def initialize(path:, root:)
      @path = path
      @root = root
    end
  end
end
