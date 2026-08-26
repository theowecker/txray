# frozen_string_literal: true

module Txray
  module Runtime
    class Transaction
      attr_reader :source, :violations

      def initialize(source)
        @source = source
        @violations = []
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def record(violation) = @violations << violation

      def duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).round(1)

      def to_event(outcome)
        {
          type: "transaction",
          at: Time.now.to_f,
          pid: Process.pid,
          duration_ms: duration_ms,
          outcome: outcome.to_s,
          source: source,
          violations: violations
        }
      end
    end

    class Stack
      KEY = :txray_transactions

      class << self
        def push(source)
          frames.push(Transaction.new(source))
        end

        def pop = frames.pop
        def current = frames.last
        def open? = !frames.empty?

        private

        def frames = Thread.current[KEY] ||= []
      end
    end
  end
end
