# frozen_string_literal: true

module Txray
  class ClientIndex
    RETURN_WRITES = [
      Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableWriteNode,
      Prism::LocalVariableOrWriteNode, Prism::LocalVariableWriteNode,
      Prism::ConstantOrWriteNode, Prism::ConstantWriteNode
    ].freeze

    def initialize(classifier)
      @classifier = classifier
      @locals = {}
      @ivars = {}
      @constants = {}
      @methods = {}
      @delegations = {}
    end

    def index(source)
      Namespaces.each(source.root) do |namespace, node|
        case node
        when Prism::LocalVariableWriteNode then bind(@locals, source.path, node.name, node.value)
        when Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode
          bind(@ivars, namespace, node.name, node.value)
        when Prism::ConstantWriteNode then bind_constant(namespace, node)
        when Prism::DefNode then bind_method(namespace, node)
        when Prism::CallNode then bind_delegation(namespace, node)
        end
      end
    end

    def kind_of(node, context, depth = 0)
      return nil if node.nil? || depth > 4

      case node
      when Prism::LocalVariableReadNode then @locals.dig(context.path, node.name)
      when Prism::InstanceVariableReadNode then @ivars.dig(context.namespace, node.name)
      when Prism::ConstantReadNode, Prism::ConstantPathNode then constant_kind(node, context.namespace)
      when Prism::CallNode then call_kind(node, context, depth)
      end
    end

    def delegated_kind(namespace, name, depth = 0)
      target = @delegations.dig(namespace, name)
      return nil if target.nil? || depth > 4

      @methods.dig(namespace, target) || delegated_kind(namespace, target, depth + 1)
    end

    private

    def call_kind(node, context, depth)
      return @methods.dig(context.namespace, node.name) if node.receiver.nil?

      constructed_kind(node) || kind_of(node.receiver, context, depth + 1)
    end

    def constructed_kind(node)
      @classifier.constructor?(node) ? @classifier.constant_rule(NodeHelpers.constant_name(node.receiver)) : nil
    end

    def constant_kind(node, namespace)
      name = NodeHelpers.constant_name(node).to_s
      @constants[qualify(namespace, name)] || @constants[name]
    end

    def qualify(namespace, name) = namespace.to_s.empty? ? name.to_s : "#{namespace}::#{name}"

    def bind(table, scope, name, value)
      kind = source_kind(value)
      (table[scope] ||= {})[name] = kind if kind
    end

    def bind_constant(namespace, node)
      kind = source_kind(node.value)
      @constants[qualify(namespace, node.name)] = kind if kind
    end

    def bind_method(namespace, node)
      kind = returned_kind(node.body)
      (@methods[namespace] ||= {})[node.name] = kind if kind
    end

    def returned_kind(body)
      node = body.is_a?(Prism::StatementsNode) ? body.body.last : body
      return source_kind(node.value) if RETURN_WRITES.any? { |type| node.is_a?(type) }

      source_kind(node)
    end

    def bind_delegation(namespace, call)
      return unless call.name == :delegate && call.receiver.nil?

      target = delegation_target(call)
      return if target.nil?

      NodeHelpers.symbol_arguments(call).each { |name| (@delegations[namespace] ||= {})[name] = target }
    end

    def delegation_target(call)
      hash = NodeHelpers.positional_arguments(call).grep(Prism::KeywordHashNode).first
      return nil if hash.nil?

      value = hash.elements.grep(Prism::AssocNode).find { |element| key_name(element) == "to" }&.value
      value.unescaped.to_sym if value.is_a?(Prism::SymbolNode)
    end

    def key_name(element)
      element.key.unescaped if element.key.respond_to?(:unescaped)
    end

    def source_kind(node)
      return nil unless node.is_a?(Prism::CallNode) && @classifier.constructor?(node)

      @classifier.constant_rule(NodeHelpers.constant_name(node.receiver))
    end
  end
end
