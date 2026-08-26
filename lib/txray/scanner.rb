# frozen_string_literal: true

module Txray
  Result = Struct.new(:offenses, :files, :skipped, keyword_init: true) do
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
      sources = []
      skipped = []
      files.each do |path|
        source = SourceFile.parse(path)
        source ? sources << source : skipped << path
      end

      Result.new(offenses: analyze(sources), files: sources.map(&:path), skipped: skipped)
    end

    def analyze(sources)
      index = MethodIndex.new
      clients = ClientIndex.new(Classifier.new(@config))
      sources.each do |source|
        index.index(source)
        clients.index(source)
      end

      analyzer = Analyzer.new(index: index, clients: clients, config: @config)
      dedupe(sources.flat_map { |source| analyzer.call(source) }).sort_by(&:sort_key)
    end

    def dedupe(offenses)
      offenses.group_by(&:key).values.map { |group| group.min_by { |offense| offense.trace.size } }
    end

    def files
      roots = @paths.empty? ? @config.includes : @paths
      verify(roots) unless @paths.empty?
      roots.flat_map { |root| expand(root).reject { |path| excluded?(path, root) } }.uniq.sort
    end

    private

    def verify(roots)
      missing = roots.reject { |root| File.exist?(root) }
      raise Error, "no such file or directory: #{missing.join(", ")}" if missing.any?
    end

    def expand(root)
      return [ root ] if File.file?(root)

      Dir.glob(File.join(root, "**", "*.rb"))
    end

    def excluded?(path, root)
      relative = path.delete_prefix(root.chomp(File::SEPARATOR)).delete_prefix(File::SEPARATOR)
      segments = relative.split(File::SEPARATOR)
      @config.excludes.any? do |pattern|
        segments.include?(pattern) || File.fnmatch?(pattern, relative, File::FNM_PATHNAME)
      end
    end
  end
end
