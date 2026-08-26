# frozen_string_literal: true

module Txray
  class Classifier
    def initialize(config)
      @config = config
      @clients = Catalog::SERVICE_NAMESPACES + config.external_clients
    end

    def call(node)
      return "shell-in-transaction" if node.is_a?(Prism::XStringNode)
      return nil unless node.is_a?(Prism::CallNode)

      name = node.name
      constant = NodeHelpers.constant_name(node.receiver)

      return "shell-in-transaction" if shell?(node, name, constant)
      return "sleep-in-transaction" if blocking?(node, name, constant)
      return "http-in-transaction" if http?(name, constant)
      return "mail-in-transaction" if Catalog::MAIL_METHODS.include?(name)
      return "job-enqueue-in-transaction" if enqueue?(name, constant)
      return "cache-in-transaction" if cache?(node, constant)
      return "blocking-io-in-transaction" if blocking_io?(name, constant)
      return "external-service-in-transaction" if Catalog.namespaced?(constant, @clients)
      return "upload-in-transaction" if Catalog::ATTACHMENT_METHODS.include?(name)

      nil
    end

    def iteration?(node)
      return false unless node.is_a?(Prism::CallNode) && node.block && Catalog::ITERATOR_METHODS.include?(node.name)

      NodeHelpers.each_node(NodeHelpers.block_body(node)) do |child|
        return true if child.is_a?(Prism::CallNode) && Catalog::PERSISTENCE_METHODS.include?(child.name)
      end
      false
    end

    private

    def shell?(node, name, constant)
      return false unless Catalog::SHELL_METHODS.include?(name)

      node.receiver.nil? || Catalog.namespaced?(constant, Catalog::SHELL_NAMESPACES)
    end

    def blocking?(node, name, constant)
      return true if name == :sleep && (node.receiver.nil? || constant == "Kernel")

      name == :timeout && constant == "Timeout"
    end

    def http?(name, constant)
      return true if Catalog.namespaced?(constant, Catalog::HTTP_NAMESPACES)

      name == :open && %w[URI OpenURI Kernel].include?(constant)
    end

    def enqueue?(name, constant)
      return true if Catalog::ENQUEUE_METHODS.include?(name)

      name == :push && constant == "Sidekiq::Client"
    end

    def blocking_io?(name, constant)
      return false if constant.nil?
      return Catalog::FILE_METHODS.include?(name) if Catalog::FILE_NAMESPACES.include?(constant)

      Catalog.namespaced?(constant, Catalog::MEDIA_NAMESPACES)
    end

    def cache?(node, constant)
      return true if Catalog.namespaced?(constant, Catalog::CACHE_NAMESPACES)

      NodeHelpers.receiver_name(node).to_s.start_with?("Rails.cache", "$redis", "@redis")
    end
  end
end
