# frozen_string_literal: true

require "logger"

module Txray
  module Runtime
    class Violation < Error; end

    class << self
      attr_reader :options

      def install(threshold_ms: 250, on_violation: :log, guard_http: true, guard_jobs: true, guard_mail: true,
                  logger: nil)
        return if @installed

        @installed = true
        @options = { threshold_ms: threshold_ms.to_i, on_violation: on_violation.to_sym, logger: logger }
        watch_transactions
        watch_jobs if guard_jobs
        watch_mail if guard_mail
        patch_net_http if guard_http
      end

      def installed? = @installed == true

      def transaction_open?
        pool = ActiveRecord::Base.connection_pool
        return false unless pool.active_connection?

        connection = pool.respond_to?(:lease_connection) ? pool.lease_connection : pool.connection
        connection.transaction_open?
      rescue StandardError
        false
      end

      def violation(message)
        text = "[txray] #{message}\n  #{app_backtrace.join("\n  ")}"
        raise Violation, text if @options[:on_violation] == :raise

        logger.warn(text)
      end

      private

      def logger = @options[:logger] || (defined?(Rails) && Rails.logger) || Logger.new($stderr)

      def app_backtrace
        root = defined?(Rails) && Rails.root ? Rails.root.to_s : Dir.pwd
        caller.select { |line| line.start_with?(root) && !line.include?("/txray/") }.first(5)
      end

      def subscribe(event, &block)
        ActiveSupport::Notifications.subscribe(event) { |*args| block.call(ActiveSupport::Notifications::Event.new(*args)) }
      end

      def watch_transactions
        subscribe("transaction.active_record") do |event|
          next if event.duration < @options[:threshold_ms]

          violation("transaction held for #{event.duration.round}ms, over the #{@options[:threshold_ms]}ms threshold")
        end
      end

      def watch_jobs
        subscribe("enqueue.active_job") do |event|
          next unless transaction_open?

          violation("#{event.payload[:job].class} was enqueued inside an open transaction")
        end
      end

      def watch_mail
        subscribe("deliver.action_mailer") do |event|
          next unless transaction_open?

          violation("#{event.payload[:mailer]} delivered mail inside an open transaction")
        end
      end

      def patch_net_http
        require "net/http"
        Net::HTTP.prepend(NetHttpGuard)
      end
    end

    module NetHttpGuard
      def request(req, body = nil, &)
        Txray::Runtime.violation("#{req.method} #{req.path} was requested inside an open transaction") if Txray::Runtime.transaction_open?
        super
      end
    end
  end
end
