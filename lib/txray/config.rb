# frozen_string_literal: true

require "yaml"
require "pathname"

module Txray
  class Config
    FILENAME = ".txray.yml"

    DEFAULTS = {
      "include" => [ "app", "lib", "db/migrate" ],
      "exclude" => %w[spec test vendor node_modules tmp log .git],
      "max_depth" => 3,
      "fail_level" => "low",
      "disabled_rules" => [],
      "external_clients" => [],
      "severities" => {},
      "runtime" => {
        "enabled" => false,
        "threshold_ms" => 250,
        "on_violation" => "log",
        "log_path" => "tmp/txray.ndjson",
        "ignore" => [],
        "guard_http" => true,
        "guard_jobs" => true,
        "guard_mail" => true
      }
    }.freeze

    def self.discover(from = Dir.pwd)
      Pathname.new(from).ascend do |directory|
        candidate = directory.join(FILENAME)
        return candidate.to_s if candidate.file?
      end
      nil
    end

    def self.load(path = nil)
      path ||= discover
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

    def rule(id)
      severity = @data["severities"].to_h[id.to_s]
      base = Rules[id]
      return base unless severity

      base.dup.tap { |copy| copy.severity = severity.to_sym }
    end

    def merge(overrides)
      self.class.new(@data.merge(overrides.compact.transform_keys(&:to_s)))
    end

    def to_h = @data
  end
end
