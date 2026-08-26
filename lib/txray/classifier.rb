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
      return "mail-in-transaction" if Catalog::MAIL_METHODS.include?(name)
      return "job-enqueue-in-transaction" if enqueue?(name, constant)
      return "broadcast-in-transaction" if broadcast?(node, name)
      return "upload-in-transaction" if Catalog::ATTACHMENT_METHODS.include?(name)
      return "external-service-in-transaction" if Catalog::SEARCH_METHODS.include?(name)
      return "dynamic-dispatch-in-transaction" if unresolvable_dispatch?(node, name)
      return "cache-in-transaction" if rails_cache?(node)
      return nil if constructor?(node, name)

      constant_rule(constant) || implicit_http(name, constant)
    end

    def constant_rule(constant)
      return nil if constant.nil?
      return "http-in-transaction" if Catalog.namespaced?(constant, Catalog::HTTP_NAMESPACES)
      return "cache-in-transaction" if Catalog.namespaced?(constant, Catalog::CACHE_NAMESPACES)
      return "blocking-io-in-transaction" if Catalog.namespaced?(constant, Catalog::MEDIA_NAMESPACES)
      return "external-service-in-transaction" if Catalog.namespaced?(constant, @clients)

      nil
    end

    def iteration?(node)
      return false unless node.is_a?(Prism::CallNode) && node.block && Catalog::ITERATOR_METHODS.include?(node.name)

      NodeHelpers.each_node(NodeHelpers.block_body(node)) do |child|
        return true if child.is_a?(Prism::CallNode) && Catalog::PERSISTENCE_METHODS.include?(child.name)
      end
      false
    end

    def constructor?(node, name = node.name)
      Catalog::CONSTRUCTOR_METHODS.include?(name) && !constant_rule(NodeHelpers.constant_name(node.receiver)).nil?
    end

    private

    def implicit_http(name, constant)
      return "http-in-transaction" if name == :open && %w[URI OpenURI Kernel].include?(constant)
      return "blocking-io-in-transaction" if file_io?(name, constant)

      nil
    end

    def file_io?(name, constant)
      Catalog::FILE_NAMESPACES.include?(constant) && Catalog::FILE_METHODS.include?(name)
    end

    def shell?(node, name, constant)
      return false unless Catalog::SHELL_METHODS.include?(name)

      node.receiver.nil? || Catalog.namespaced?(constant, Catalog::SHELL_NAMESPACES)
    end

    def blocking?(node, name, constant)
      return true if name == :sleep && (node.receiver.nil? || constant == "Kernel")

      name == :timeout && constant == "Timeout"
    end

    def enqueue?(name, constant)
      return true if Catalog::ENQUEUE_METHODS.include?(name)

      name == :push && constant == "Sidekiq::Client"
    end

    def broadcast?(node, name)
      return true if Catalog::BROADCAST_METHODS.include?(name)

      name == :broadcast && NodeHelpers.receiver_name(node).to_s.start_with?("ActionCable")
    end

    def unresolvable_dispatch?(node, name)
      return false unless Catalog::DISPATCH_METHODS.include?(name)

      argument = NodeHelpers.positional_arguments(node).first
      !argument.nil? && !argument.is_a?(Prism::SymbolNode)
    end

    def rails_cache?(node)
      NodeHelpers.receiver_name(node).to_s.start_with?("Rails.cache", "$redis", "@redis")
    end
  end
end
