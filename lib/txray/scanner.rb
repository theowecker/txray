# frozen_string_literal: true

module Txray
  Result = Struct.new(:offenses, :files, keyword_init: true) do
    def counts = offenses.group_by(&:severity).transform_values(&:size)
    def worst = offenses.map(&:severity_rank).max
    def failing?(level) = worst && worst >= (Offense::SEVERITIES.index(level) || Offense::SEVERITIES.size)
  end

  class Scanner
    def initialize(config, paths: nil)
      @config = config
      @paths = Array(paths).reject(&:empty?)
    end

    def run
      sources = files.filter_map { |path| SourceFile.parse(path) }
      index = MethodIndex.new
      sources.each { |source| index.index(source) }
      analyzer = Analyzer.new(index: index, config: @config)

      offenses = sources.flat_map { |source| analyzer.call(source) }
      Result.new(offenses: dedupe(offenses).sort_by(&:sort_key), files: sources.map(&:path))
    end

    def dedupe(offenses)
      offenses.group_by(&:key).values.map { |group| group.min_by { |offense| offense.trace.size } }
    end

    def files
      roots = @paths.empty? ? @config.includes : @paths
      roots.flat_map { |root| expand(root) }.uniq.reject { |path| excluded?(path) }.sort
    end

    private

    def expand(root)
      return [ root ] if File.file?(root)

      Dir.glob(File.join(root, "**", "*.rb"))
    end

    def excluded?(path)
      segments = path.split(File::SEPARATOR)
      @config.excludes.any? { |pattern| segments.include?(pattern) || File.fnmatch?(pattern, path, File::FNM_PATHNAME) }
    end
  end
end
