# frozen_string_literal: true

module Txray
  class ClientIndex
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
        when Prism::LocalVariableWriteNode then bind(@locals, node.name, node.value)
        when Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode then bind(@ivars, node.name, node.value)
        when Prism::ConstantWriteNode then bind(@constants, node.name, node.value)
        when Prism::DefNode then bind_method(namespace, node)
        when Prism::CallNode then bind_delegation(namespace, node)
        end
      end
    end

    def kind_of(node, namespace, depth = 0)
      return nil if node.nil? || depth > 4

      case node
      when Prism::LocalVariableReadNode then @locals[node.name]
      when Prism::InstanceVariableReadNode then @ivars[node.name]
      when Prism::ConstantReadNode, Prism::ConstantPathNode then constant_kind(node)
      when Prism::CallNode then call_kind(node, namespace, depth)
      end
    end

    def delegated_kind(namespace, name, depth = 0)
      target = @delegations.dig(namespace, name)
      return nil if target.nil? || depth > 4

      @methods.dig(namespace, target) || delegated_kind(namespace, target, depth + 1)
    end

    private

    def call_kind(node, namespace, depth)
      return @methods.dig(namespace, node.name) if node.receiver.nil?

      constructed_kind(node) || kind_of(node.receiver, namespace, depth + 1)
    end

    def constructed_kind(node)
      @classifier.constructor?(node) ? @classifier.constant_rule(NodeHelpers.constant_name(node.receiver)) : nil
    end

    def constant_kind(node)
      name = NodeHelpers.constant_name(node)
      @constants[name.to_s.split("::").last.to_sym]
    end

    def bind(table, name, value)
      kind = source_kind(value)
      table[name] = kind if kind
    end

    def bind_method(namespace, node)
      return if node.body.nil?

      kind = nil
      NodeHelpers.each_node(node.body) { |child| kind ||= source_kind(child) }
      (@methods[namespace] ||= {})[node.name] = kind if kind
    end

    def bind_delegation(namespace, call)
      return unless call.name == :delegate && call.receiver.nil?

      target = delegation_target(call)
      return if target.nil?

      NodeHelpers.symbol_arguments(call).each { |name| (@delegations[namespace] ||= {})[name] = target }
    end

    def delegation_target(call)
      hash = NodeHelpers.positional_arguments(call).grep(Prism::KeywordHashNode).first
      pair = hash&.elements&.grep(Prism::AssocNode)&.find { |element| element.key.respond_to?(:unescaped) && element.key.unescaped == "to" }
      pair&.value.then { |value| value.unescaped.to_sym if value.is_a?(Prism::SymbolNode) }
    end

    def source_kind(node)
      return nil unless node.is_a?(Prism::CallNode) && @classifier.constructor?(node)

      @classifier.constant_rule(NodeHelpers.constant_name(node.receiver))
    end
  end
end
