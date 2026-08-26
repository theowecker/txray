# frozen_string_literal: true

module Txray
  MethodEntry = Struct.new(:namespace, :name, :node, :source, :singleton, keyword_init: true) do
    def label = "#{namespace}#{singleton ? "." : "#"}#{name}"
    def line = node.location.start_line
    def path = source.path
  end

  class MethodIndex
    MAX_RESOLUTION_DEPTH = 4

    def initialize
      @instance = {}
      @singleton = {}
      @includes = {}
    end

    def index(source)
      Namespaces.each(source.root) do |namespace, node|
        case node
        when Prism::DefNode then add_method(namespace, node, source)
        when Prism::CallNode then add_include(namespace, node)
        end
      end
    end

    def unique(name)
      matches = @instance.each_value.filter_map { |methods| methods[name] }
      matches.first if matches.size == 1
    end

    def lookup(namespace, name, singleton: false, depth: 0)
      return nil if namespace.nil? || namespace.empty? || depth > MAX_RESOLUTION_DEPTH

      table = singleton ? @singleton : @instance
      direct = table.dig(namespace, name)
      return direct if direct

      from_modules(namespace, name, singleton, depth) || from_lexical_parent(namespace, name, singleton, depth)
    end

    private

    def add_method(namespace, node, source)
      singleton = !node.receiver.nil?
      table = singleton ? @singleton : @instance
      entry = MethodEntry.new(namespace: namespace, name: node.name.to_sym, node: node, source: source,
                              singleton: singleton)
      (table[namespace] ||= {})[entry.name] ||= entry
    end

    def add_include(namespace, node)
      return unless node.receiver.nil? && %i[include prepend extend].include?(node.name)

      NodeHelpers.positional_arguments(node).each do |argument|
        name = NodeHelpers.constant_name(argument)
        (@includes[namespace] ||= []) << name if name
      end
    end

    def from_modules(namespace, name, singleton, depth)
      @includes.fetch(namespace, []).each do |mod|
        resolved = resolve_namespace(namespace, mod)
        entry = resolved && lookup(resolved, name, singleton: singleton, depth: depth + 1)
        return entry if entry
      end
      nil
    end

    def from_lexical_parent(namespace, name, singleton, depth)
      parent = namespace.split("::")[0..-2].join("::")
      parent.empty? ? nil : lookup(parent, name, singleton: singleton, depth: depth + 1)
    end

    def resolve_namespace(from, mod)
      segments = from.split("::")
      candidates = segments.each_index.map { |i| (segments[0..i] + [ mod ]).join("::") }.reverse
      (candidates + [ mod ]).find { |candidate| known?(candidate) }
    end

    def known?(namespace)
      @instance.key?(namespace) || @singleton.key?(namespace) || @includes.key?(namespace)
    end
  end

  module Namespaces
    module_function

    def each(node, namespace = "", &block)
      return if node.nil?

      case node
      when Prism::ClassNode, Prism::ModuleNode
        child = join(namespace, NodeHelpers.constant_name(node.constant_path))
        block.call(child, node)
        each(node.body, child, &block)
      when Prism::SingletonClassNode
        each(node.body, namespace, &block)
      else
        block.call(namespace, node)
        node.compact_child_nodes.each { |c| each(c, namespace, &block) }
      end
    end

    def join(namespace, name)
      return namespace if name.nil?

      namespace.empty? ? name : "#{namespace}::#{name}"
    end
  end
end
