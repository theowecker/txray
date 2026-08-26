# frozen_string_literal: true

require "logger"
require "fileutils"

require_relative "runtime/sink"
require_relative "runtime/transaction"

module Txray
  module Runtime
    class Violation < Error; end

    IGNORE_KEY = :txray_ignoring
    GEM_ROOT = File.expand_path("..", __dir__)

    DEFAULTS = {
      threshold_ms: 250,
      on_violation: :log,
      guard_http: true,
      guard_jobs: true,
      guard_mail: true,
      log_path: nil,
      ignore: [],
      logger: nil
    }.freeze

    class << self
      attr_reader :options

      def install(**overrides)
        return if @installed

        @installed = true
        @options = DEFAULTS.merge(overrides.compact)
        @ignore = Array(@options[:ignore]).map { |pattern| Regexp.new(pattern.to_s) }
        @sink = Sink.build(@options[:log_path])
        @subscribers = []

        watch_transactions
        watch_jobs if @options[:guard_jobs]
        watch_mail if @options[:guard_mail]
        patch_net_http if @options[:guard_http]
      end

      def uninstall
        @subscribers.to_a.each { |subscriber| ActiveSupport::Notifications.unsubscribe(subscriber) }
        @subscribers = []
        @installed = nil
      end

      def installed? = @installed == true

      def ignore
        previous = Thread.current[IGNORE_KEY]
        Thread.current[IGNORE_KEY] = true
        yield
      ensure
        Thread.current[IGNORE_KEY] = previous
      end

      def ignoring? = Thread.current[IGNORE_KEY] == true

      def transaction_open?
        return false unless defined?(ActiveRecord::Base)

        pool = ActiveRecord::Base.connection_pool
        return false unless pool.active_connection?

        connection = pool.respond_to?(:lease_connection) ? pool.lease_connection : pool.connection
        connection.transaction_open?
      rescue StandardError
        false
      end

      def violation(rule, message, duration_ms: nil)
        return if ignoring?

        source = app_backtrace.first
        return if ignored?("#{message} #{source}")

        record = { rule: rule, message: message, duration_ms: duration_ms, source: source }
        open = Stack.current
        open&.record(record)
        report(record.merge(type: "violation", at: Time.now.to_f, pid: Process.pid)) if open.nil?
        announce(rule, message)
      end

      def report(event)
        @sink.write(event)
      end

      private

      def announce(rule, message)
        text = "[txray] #{rule}: #{message}\n  #{app_backtrace.join("\n  ")}"
        raise Violation, text if @options[:on_violation] == :raise

        logger.warn(text)
      end

      def ignored?(text) = @ignore.any? { |pattern| pattern.match?(text) }

      def logger = @options[:logger] || (defined?(Rails) && Rails.logger) || Logger.new($stderr)

      def app_backtrace
        root = defined?(Rails) && Rails.root ? Rails.root.to_s : Dir.pwd
        frames = caller.reject { |line| line.start_with?(GEM_ROOT) }
        own = frames.select { |line| line.start_with?(root) }
        own = frames.reject { |line| line.include?("/gems/") || line.start_with?(RbConfig::CONFIG["libdir"]) } if own.empty?
        own.map { |line| line.delete_prefix("#{root}/") }.first(5)
      end

      def subscribe(event, &block)
        @subscribers << ActiveSupport::Notifications.subscribe(event) do |*args|
          block.call(ActiveSupport::Notifications::Event.new(*args))
        end
      end

      def watch_transactions
        subscribe("start_transaction.active_record") { open_transaction }
        subscribe("transaction.active_record") { |event| close_transaction(event) }
      end

      def open_transaction
        Stack.push(app_backtrace.first)
      end

      def close_transaction(event)
        transaction = Stack.pop
        return if ignoring?

        duration = transaction&.duration_ms || event.duration.round(1)
        slow = duration >= @options[:threshold_ms]
        violations = transaction&.violations.to_a
        return unless slow || violations.any?

        outcome = event.payload[:outcome] || :commit
        report((transaction&.to_event(outcome) || fallback_event(duration, outcome)).merge(duration_ms: duration))
        announce_slow(duration) if slow
      end

      def fallback_event(duration, outcome)
        { type: "transaction", at: Time.now.to_f, pid: Process.pid, duration_ms: duration,
          outcome: outcome.to_s, source: app_backtrace.first, violations: [] }
      end

      def announce_slow(duration)
        announce("slow-transaction",
                 "transaction held for #{duration}ms, over the #{@options[:threshold_ms]}ms threshold")
      end

      def watch_jobs
        subscribe("enqueue.active_job") do |event|
          next unless transaction_open?

          violation("job-enqueue-in-transaction", "#{event.payload[:job].class} enqueued inside an open transaction")
        end
      end

      def watch_mail
        subscribe("deliver.action_mailer") do |event|
          next unless transaction_open?

          violation("mail-in-transaction", "#{event.payload[:mailer]} delivered mail inside an open transaction",
                    duration_ms: event.duration.round(1))
        end
      end

      def patch_net_http
        return if @http_patched

        require "net/http"
        Net::HTTP.prepend(NetHttpGuard)
        @http_patched = true
      end
    end

    module NetHttpGuard
      def request(req, body = nil, &)
        return super unless Txray::Runtime.transaction_open?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          super
        ensure
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
          Txray::Runtime.violation("http-in-transaction", "#{req.method} #{address}#{req.path} inside an open " \
                                                          "transaction", duration_ms: elapsed)
        end
      end
    end
  end
end
