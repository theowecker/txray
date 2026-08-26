# frozen_string_literal: true

require_relative "reporters/text"
require_relative "reporters/json"
require_relative "reporters/sarif"
require_relative "reporters/github"
require_relative "reporters/live"

module Txray
  module Reporters
    def self.color?(io)
      ENV["NO_COLOR"].to_s.empty? && io.respond_to?(:tty?) && io.tty?
    end

    FORMATS = { "text" => Text, "json" => Json, "sarif" => Sarif, "github" => Github }.freeze

    def self.build(format, io: $stdout)
      klass = FORMATS[format.to_s] or raise Error, "unknown format #{format}, expected one of #{FORMATS.keys.join(", ")}"
      klass.new(io: io)
    end
  end
end
