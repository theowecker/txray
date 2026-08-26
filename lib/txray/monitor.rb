# frozen_string_literal: true

require "json"

module Txray
  class Monitor
    CAP = 2000

    attr_reader :transactions, :violations, :started_at

    def initialize(threshold_ms: 250)
      @threshold_ms = threshold_ms
      @transactions = []
      @violations = []
      @recent = []
      @started_at = Time.now
    end

    def absorb(line)
      event = JSON.parse(line, symbolize_names: true)
      case event[:type]
      when "transaction" then add(@transactions, event)
      when "violation" then add(@violations, event)
      else return nil
      end
      @recent.unshift(event)
      @recent.pop while @recent.size > 40
      event
    rescue JSON::ParserError
      nil
    end

    BUCKETS = [ [ 10, "<10ms" ], [ 50, "<50ms" ], [ 100, "<100ms" ], [ 250, "<250ms" ],
                [ 1000, "<1s" ], [ Float::INFINITY, "1s+" ] ].freeze

    def recent(limit) = @recent.first(limit)
    def pids = @transactions.map { |event| event[:pid] }.uniq.size

    def breakdown
      flagged = @transactions.count { |event| event[:violations].to_a.any? }
      slow = @transactions.count { |event| slow?(event) && event[:violations].to_a.empty? }
      { ok: @transactions.size - flagged - slow, slow: slow, flagged: flagged }
    end

    def histogram
      BUCKETS.map do |limit, label|
        { label: label, limit: limit,
          count: durations.count { |value| value < limit && value >= previous_limit(limit) } }
      end
    end

    def durations = @transactions.map { |event| event[:duration_ms].to_f }
    def slow = @transactions.count { |event| slow?(event) }
    def slow?(event) = event[:duration_ms].to_f >= @threshold_ms
    def flagged = @transactions.count { |event| event[:violations].to_a.any? }
    def uptime = Time.now - @started_at
    def empty? = @transactions.empty? && @violations.empty?

    def percentile(fraction)
      values = durations.sort
      return 0.0 if values.empty?

      values[[ (values.size * fraction).ceil - 1, 0 ].max]
    end

    def findings
      nested = @transactions.flat_map { |event| event[:violations].to_a }
      slow = @transactions.select { |event| event[:duration_ms].to_f >= @threshold_ms }
                          .map { |event| { rule: "slow-transaction", source: event[:source] } }
      @violations + nested + slow
    end

    def hotspots(limit)
      findings.group_by { |event| [ event[:rule], event[:source] ] }
              .map { |(rule, source), events| { rule: rule, source: source, count: events.size } }
              .sort_by { |entry| -entry[:count] }
              .first(limit)
    end

    private

    def previous_limit(limit)
      index = BUCKETS.index { |bucket_limit, _| bucket_limit == limit }
      index.zero? ? 0 : BUCKETS[index - 1].first
    end

    def add(collection, event)
      collection << event
      collection.shift while collection.size > CAP
    end
  end
end
