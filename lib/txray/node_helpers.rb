# frozen_string_literal: true

module Txray
  module NodeHelpers
    module_function

    def each_node(node, &block)
      return if node.nil?

      block.call(node)
      node.compact_child_nodes.each { |child| each_node(child, &block) }
    end

    def constant_name(node)
      case node
      when Prism::ConstantReadNode
        node.name.to_s
      when Prism::ConstantPathNode
        [ constant_name(node.parent), constant_path_child(node) ].compact.reject(&:empty?).join("::")
      when Prism::SelfNode
        "self"
      end
    end

    def constant_path_child(node)
      return node.name.to_s if node.respond_to?(:name) && node.name
      return constant_name(node.child) if node.respond_to?(:child)

      nil
    end

    def symbol_arguments(call)
      positional_arguments(call).grep(Prism::SymbolNode).map { |symbol| symbol.unescaped.to_sym }
    end

    def positional_arguments(call)
      call.arguments&.arguments.to_a
    end

    def block_body(call)
      call.block.body if call.block.is_a?(Prism::BlockNode)
    end

    def receiver_name(call)
      constant_name(call.receiver) || dynamic_receiver_name(call.receiver)
    end

    def dynamic_receiver_name(node)
      case node
      when Prism::CallNode
        [ receiver_name(node), node.name ].compact.join(".")
      when Prism::InstanceVariableReadNode, Prism::GlobalVariableReadNode, Prism::LocalVariableReadNode
        node.name.to_s
      end
    end

    def snippet(node, limit = 90)
      text = node.slice.to_s.lines.first.to_s.strip
      text.length > limit ? "#{text[0, limit - 3]}..." : text
    end
  end
end
