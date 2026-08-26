# frozen_string_literal: true

module Txray
  class Analyzer
    def initialize(index:, config:)
      @index = index
      @config = config
      @classifier = Classifier.new(config)
      @scope_finder = ScopeFinder.new(index)
    end

    def call(source)
      offenses = {}
      @scope_finder.call(source).each do |scope|
        explore(scope.body, scope.namespace, scope.source, scope, 0, [], Set.new) do |offense|
          current = offenses[offense.key]
          offenses[offense.key] = offense if current.nil? || offense.trace.size < current.trace.size
        end
      end
      offenses.values
    end

    private

    def explore(node, namespace, source, scope, depth, trace, visited, &emit)
      NodeHelpers.each_node(node) do |current|
        report(current, source, scope, trace, &emit)
        follow(current, namespace, scope, depth, trace, visited, &emit) if current.is_a?(Prism::CallNode)
      end
    end

    def report(node, source, scope, trace, &emit)
      rule_id = @classifier.call(node) || (@classifier.iteration?(node) ? "iteration-in-transaction" : nil)
      return unless rule_id && @config.rule_enabled?(rule_id)

      emit.call(Offense.new(
                  rule: Rules[rule_id],
                  path: source.path,
                  line: node.location.start_line,
                  column: node.location.start_column + 1,
                  snippet: NodeHelpers.snippet(node),
                  scope: scope,
                  trace: trace
                ))
    end

    def follow(call, namespace, scope, depth, trace, visited, &)
      return unless depth < @config.max_depth

      entry = resolve(call, namespace)
      return if entry.nil? || entry.node.body.nil?
      return unless visited.add?([ entry.namespace, entry.name ])

      frame = Frame.new(label: entry.label, path: entry.path, line: entry.line)
      explore(entry.node.body, entry.namespace, entry.source, scope, depth + 1, trace + [ frame ], visited, &)
    end

    def resolve(call, namespace)
      case call.receiver
      when nil
        @index.lookup(namespace, call.name)
      when Prism::SelfNode
        @index.lookup(namespace, call.name, singleton: true) || @index.lookup(namespace, call.name)
      when Prism::ConstantReadNode, Prism::ConstantPathNode
        @index.lookup(NodeHelpers.constant_name(call.receiver), call.name, singleton: true)
      when Prism::CallNode
        resolve_instance(call)
      end
    end

    def resolve_instance(call)
      receiver = call.receiver
      return unless receiver.name == :new

      owner = NodeHelpers.constant_name(receiver.receiver)
      owner && @index.lookup(owner, call.name)
    end
  end
end
