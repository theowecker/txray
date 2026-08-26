# frozen_string_literal: true

require "yaml"

module Txray
  class Config
    FILENAME = ".txray.yml"

    DEFAULTS = {
      "include" => %w[app lib],
      "exclude" => %w[spec test vendor node_modules tmp log .git],
      "max_depth" => 3,
      "fail_level" => "low",
      "disabled_rules" => [],
      "external_clients" => [],
      "runtime" => {
        "enabled" => false,
        "threshold_ms" => 250,
        "on_violation" => "log",
        "guard_http" => true,
        "guard_jobs" => true,
        "guard_mail" => true
      }
    }.freeze

    def self.load(path = nil)
      path ||= Dir.glob(FILENAME).first
      data = path && File.exist?(path) ? YAML.safe_load_file(path) : {}
      new(data.is_a?(Hash) ? data : {})
    end

    def initialize(data = {})
      @data = DEFAULTS.merge(data) { |_key, default, given| default.is_a?(Hash) ? default.merge(given.to_h) : given }
    end

    def includes = Array(@data["include"])
    def excludes = Array(@data["exclude"])
    def max_depth = Integer(@data["max_depth"])
    def external_clients = Array(@data["external_clients"]).map(&:to_s)
    def disabled_rules = Array(@data["disabled_rules"]).map(&:to_s)
    def runtime = @data["runtime"].transform_keys(&:to_s)

    def fail_level = @data["fail_level"].to_s.to_sym

    def rule_enabled?(id) = !disabled_rules.include?(id.to_s)

    def merge(overrides)
      self.class.new(@data.merge(overrides.compact.transform_keys(&:to_s)))
    end

    def to_h = @data
  end
end
