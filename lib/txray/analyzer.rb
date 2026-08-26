# frozen_string_literal: true

require "set"

module Txray
  class Analyzer
    def initialize(index:, clients:, config:)
      @index = index
      @clients = clients
      @config = config
      @classifier = Classifier.new(config)
      @scope_finder = ScopeFinder.new(index)
    end

    def call(source)
      offenses = {}
      @scope_finder.call(source).each do |scope|
        walk = Walk.new(scope: scope, suppressed: Set.new, visited: Set.new)
        explore(scope.body, scope.namespace, scope.source, walk, 0, []) do |offense|
          current = offenses[offense.key]
          offenses[offense.key] = offense if current.nil? || offense.trace.size < current.trace.size
        end
      end
      offenses.values
    end

    private

    Walk = Struct.new(:scope, :suppressed, :visited, keyword_init: true)

    def explore(node, namespace, source, walk, depth, trace, &emit)
      NodeHelpers.each_node(node) do |current|
        report(current, namespace, source, walk, trace, &emit)
        follow(current, namespace, walk, depth, trace, &emit) if current.is_a?(Prism::CallNode)
      end
    end

    def report(node, namespace, source, walk, trace, &emit)
      return if walk.suppressed.include?(node.object_id)

      rule_id = rule_for(node, namespace)
      return unless rule_id && @config.rule_enabled?(rule_id)

      suppress_receivers(node, walk)
      emit.call(Offense.new(rule: Rules[rule_id], path: source.path, line: node.location.start_line,
                            column: node.location.start_column + 1, snippet: NodeHelpers.snippet(node),
                            scope: walk.scope, trace: trace))
    end

    def rule_for(node, namespace)
      @classifier.call(node) || client_rule(node, namespace) ||
        (@classifier.iteration?(node) ? "iteration-in-transaction" : nil)
    end

    def client_rule(node, namespace)
      return nil unless node.is_a?(Prism::CallNode)
      return @clients.delegated_kind(namespace, node.name) if node.receiver.nil?

      @clients.kind_of(node.receiver, namespace)
    end

    def suppress_receivers(node, walk)
      receiver = node.receiver if node.is_a?(Prism::CallNode)
      while receiver.is_a?(Prism::CallNode)
        walk.suppressed << receiver.object_id
        receiver = receiver.receiver
      end
    end

    def follow(call, namespace, walk, depth, trace, &emit)
      return unless depth < @config.max_depth

      entry = resolve(call, namespace)
      return if entry.nil? || entry.node.body.nil?
      return unless walk.visited.add?([ entry.namespace, entry.name ])

      frame = Frame.new(label: entry.label, path: entry.path, line: entry.line)
      explore(entry.node.body, entry.namespace, entry.source, walk, depth + 1, trace + [ frame ], &emit)
    end

    def resolve(call, namespace)
      name = dispatched_name(call)
      return nil if name.nil?

      case call.receiver
      when nil then @index.lookup(namespace, name)
      when Prism::SelfNode then @index.lookup(namespace, name, singleton: true) || @index.lookup(namespace, name)
      when Prism::ConstantReadNode, Prism::ConstantPathNode
        @index.lookup(NodeHelpers.constant_name(call.receiver), name, singleton: true)
      when Prism::CallNode then resolve_instance(call, name)
      end
    end

    def dispatched_name(call)
      return call.name unless Catalog::DISPATCH_METHODS.include?(call.name)

      argument = NodeHelpers.positional_arguments(call).first
      argument.unescaped.to_sym if argument.is_a?(Prism::SymbolNode)
    end

    def resolve_instance(call, name)
      receiver = call.receiver
      return unless receiver.name == :new

      owner = NodeHelpers.constant_name(receiver.receiver)
      owner && @index.lookup(owner, name)
    end
  end
end
