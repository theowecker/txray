# frozen_string_literal: true

module Txray
  TransactionScope = Struct.new(:kind, :label, :body, :namespace, :source, :line, keyword_init: true) do
    def path = source.path
  end

  class ScopeFinder
    LOCK_BLOCKS = %i[with_lock with_advisory_lock].freeze

    def initialize(index)
      @index = index
    end

    def call(source)
      migrations = Set.new
      modules = Set.new
      scopes = []

      Namespaces.each(source.root) do |namespace, node|
        case node
        when Prism::ClassNode then migrations << namespace if transactional_migration?(node)
        when Prism::ModuleNode then modules << namespace
        when Prism::CallNode then scopes.concat(from_call(namespace, node, source, modules))
        when Prism::DefNode then scopes.concat(from_definition(namespace, node, source, migrations))
        end
      end

      scopes.compact
    end

    private

    def from_call(namespace, call, source, modules)
      case call.name
      when *Catalog::CALLBACKS then registration_scopes(namespace, call, source, "callback", modules)
      when :validate then registration_scopes(namespace, call, source, "validation", modules)
      when :transaction then [ block_scope(namespace, call, source, :transaction, transaction_label(call)) ]
      when *LOCK_BLOCKS then [ block_scope(namespace, call, source, :lock, "a `#{call.name}` block") ]
      else []
      end
    end

    def registration_scopes(namespace, call, source, noun, modules)
      return [] unless call.receiver.nil?

      scopes = NodeHelpers.symbol_arguments(call).filter_map do |method_name|
        entry = @index.lookup(namespace, method_name)
        entry ||= @index.unique(method_name) if modules.include?(namespace)
        next unless entry&.node&.body

        TransactionScope.new(
          kind: :callback,
          label: "the `#{call.name} :#{method_name}` #{noun}",
          body: entry.node.body,
          namespace: entry.namespace,
          source: entry.source,
          line: call.location.start_line
        )
      end

      scopes << block_scope(namespace, call, source, :callback, "the `#{call.name}` #{noun} block")
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

    def from_definition(namespace, node, source, migrations)
      return [] if node.body.nil?

      if migrations.include?(namespace) && Catalog::MIGRATION_METHODS.include?(node.name)
        return [ scope_for(:migration, "`#{namespace}##{node.name}`, which runs in a DDL transaction", node,
                           namespace, source) ]
      end

      return [] unless locks_row?(node.body)

      [ scope_for(:lock, "`#{namespace}##{node.name}`, which locks a row", node, namespace, source) ]
    end

    def scope_for(kind, label, node, namespace, source)
      TransactionScope.new(
        kind: kind,
        label: label,
        body: node.body,
        namespace: namespace,
        source: source,
        line: node.location.start_line
      )
    end

    def transactional_migration?(node)
      return false unless node.superclass&.slice.to_s.include?("ActiveRecord::Migration")

      NodeHelpers.each_node(node.body) do |child|
        return false if child.is_a?(Prism::CallNode) && child.name == :disable_ddl_transaction!
      end
      true
    end

    def locks_row?(body)
      NodeHelpers.each_node(body) do |node|
        return true if node.is_a?(Prism::CallNode) && node.name == :lock! && node.block.nil?
      end
      false
    end
  end
end
