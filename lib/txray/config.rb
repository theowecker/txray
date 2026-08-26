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
      raise Error, "no such config file: #{path}" if path && !File.exist?(path)

      path ||= discover
      data = path ? YAML.safe_load_file(path) : {}
      new(data.is_a?(Hash) ? data : {})
    end

    ARRAY_KEYS = %w[include exclude disabled_rules external_clients].freeze
    HASH_KEYS = %w[severities runtime].freeze
    FAIL_LEVELS = %w[low medium high none].freeze

    def initialize(data = {})
      validate!(data)
      @data = DEFAULTS.merge(data) { |_key, default, given| default.is_a?(Hash) ? default.merge(given) : given }
    end

    def includes = Array(@data["include"])
    def excludes = Array(@data["exclude"])
    def max_depth = Integer(@data["max_depth"])
    def external_clients = Array(@data["external_clients"]).map(&:to_s)
    def disabled_rules = Array(@data["disabled_rules"]).map(&:to_s)
    def runtime = @data["runtime"].transform_keys(&:to_s)

    def fail_level = @data["fail_level"].to_s.to_sym

    def rule_enabled?(id) = !disabled_rules.include?(id.to_s)

    def validate!(data)
      ARRAY_KEYS.each { |key| expect(data, key, Array) }
      HASH_KEYS.each { |key| expect(data, key, Hash) }

      depth = data["max_depth"]
      raise Error, "max_depth must be a whole number, got #{depth.inspect}" if depth && !depth.is_a?(Integer)

      level = data["fail_level"]
      return if level.nil? || FAIL_LEVELS.include?(level.to_s)

      raise Error, "fail_level must be one of #{FAIL_LEVELS.join(", ")}, got #{level.inspect}"
    end

    def expect(data, key, type)
      value = data[key]
      return if value.nil? || value.is_a?(type)

      raise Error, "#{key} must be #{type == Array ? "a list" : "a mapping"}, got #{value.inspect}"
    end

    def rule(id)
      severity = @data["severities"].to_h[id.to_s]
      base = Rules[id]
      return base unless severity

      base.dup.tap { |copy| copy.severity = severity.to_sym }
    end

    def merge(overrides)
      self.class.new(@data.merge(overrides.compact.transform_keys(&:to_s)))
    end

    private :validate!, :expect

    def to_h = @data
  end
end
