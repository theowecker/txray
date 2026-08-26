# frozen_string_literal: true

module Txray
  TransactionScope = Struct.new(:kind, :label, :body, :namespace, :source, :line, keyword_init: true) do
    def path = source.path
  end

  class ScopeFinder
    def initialize(index)
      @index = index
    end

    def call(source)
      scopes = []
      Namespaces.each(source.root) do |namespace, node|
        case node
        when Prism::CallNode then scopes.concat(from_call(namespace, node, source))
        when Prism::DefNode then scopes.concat(from_definition(namespace, node, source))
        end
      end
      scopes.compact
    end

    private

    def from_call(namespace, call, source)
      case call.name
      when *Catalog::CALLBACKS then callback_scopes(namespace, call, source)
      when :transaction then [ block_scope(namespace, call, source, :transaction, transaction_label(call)) ]
      when :with_lock then [ block_scope(namespace, call, source, :lock, "a `with_lock` block") ]
      else []
      end
    end

    def callback_scopes(namespace, call, source)
      return [] unless call.receiver.nil?

      scopes = NodeHelpers.symbol_arguments(call).filter_map do |method_name|
        entry = @index.lookup(namespace, method_name)
        next unless entry&.node&.body

        TransactionScope.new(
          kind: :callback,
          label: "the `#{call.name} :#{method_name}` callback",
          body: entry.node.body,
          namespace: entry.namespace,
          source: entry.source,
          line: call.location.start_line
        )
      end

      scopes << block_scope(namespace, call, source, :callback, "the `#{call.name}` callback block")
      scopes
    end

    def block_scope(namespace, call, source, kind, label)
      body = NodeHelpers.block_body(call)
      return unless body

      TransactionScope.new(
        kind: kind,
        label: label,
        body: body,
        namespace: namespace,
        source: source,
        line: call.location.start_line
      )
    end

    def transaction_label(call)
      receiver = NodeHelpers.receiver_name(call)
      receiver ? "the `#{receiver}.transaction` block" : "an explicit `transaction` block"
    end

    def from_definition(namespace, node, source)
      return [] unless node.body && locks_row?(node.body)

      [ TransactionScope.new(
        kind: :lock,
        label: "`#{namespace}##{node.name}`, which locks a row",
        body: node.body,
        namespace: namespace,
        source: source,
        line: node.location.start_line
      ) ]
    end

    def locks_row?(body)
      NodeHelpers.each_node(body) do |node|
        return true if node.is_a?(Prism::CallNode) && node.name == :lock! && node.block.nil?
      end
      false
    end
  end
end
