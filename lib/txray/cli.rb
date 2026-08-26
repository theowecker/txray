# frozen_string_literal: true

require "optparse"

module Txray
  class CLI
    EXIT_CLEAN = 0
    EXIT_OFFENSES = 1
    EXIT_ERROR = 2

    def self.start(argv, io: $stdout) = new(io: io).run(argv)

    def initialize(io: $stdout)
      @io = io
      @options = {}
    end

    def run(argv)
      paths = parser.parse(argv)
      return init_config if @options[:init]
      return watch if paths.first == "watch"

      config = Config.load(@options[:config]).merge(
        "fail_level" => @options[:fail_level],
        "disabled_rules" => @options[:disabled_rules],
        "max_depth" => @options[:max_depth]
      )

      result = Scanner.new(config, paths: paths).run
      result = filter(result)
      Reporters.build(@options.fetch(:format, "text"), io: @io).report(result)
      result.failing?(config.fail_level) ? EXIT_OFFENSES : EXIT_CLEAN
    rescue OptionParser::ParseError, Error => e
      @io.puts "txray: #{e.message}"
      EXIT_ERROR
    end

    private

    def filter(result)
      return result unless @options[:only]

      Result.new(offenses: result.offenses.select { |offense| @options[:only].include?(offense.id) },
                 files: result.files, skipped: result.skipped)
    end

    def watch
      runtime = Config.load(@options[:config]).runtime
      WatchCommand.new(
        path: @options[:file] || runtime["log_path"],
        threshold_ms: (@options[:threshold] || runtime["threshold_ms"]).to_i,
        io: @io,
        from_start: @options[:from_start] == true
      ).run
      EXIT_CLEAN
    end

    def init_config
      if File.exist?(Config::FILENAME)
        @io.puts "#{Config::FILENAME} already exists"
        return EXIT_ERROR
      end

      File.write(Config::FILENAME, YAML.dump(Config::DEFAULTS))
      @io.puts "created #{Config::FILENAME}"
      @io.puts
      @io.puts "scan with:            bundle exec txray"
      @io.puts "watch transactions:   set runtime.enabled to true, restart, then bundle exec txray watch"
      EXIT_CLEAN
    end

    def parser
      OptionParser.new do |opts|
        opts.banner = "Usage: txray [options] [paths]\n       txray watch [options]"
        opts.on("-f", "--format FORMAT", "text, json, sarif or github (default: text)") { |v| @options[:format] = v }
        opts.on("-c", "--config PATH", "path to a .txray.yml file") { |v| @options[:config] = v }
        opts.on("--fail-level LEVEL", "low, medium, high or none (default: low)") { |v| @options[:fail_level] = v }
        opts.on("--only RULES", Array, "report only these rule ids") { |v| @options[:only] = v }
        opts.on("--except RULES", Array, "skip these rule ids") { |v| @options[:disabled_rules] = v }
        opts.on("--depth N", Integer, "how far to follow method calls (default: 3)") { |v| @options[:max_depth] = v }
        opts.on("--rules", "list every rule and exit") { list_rules }
        opts.on("--init", "write a default .txray.yml") { @options[:init] = true }
        opts.on("--file PATH", "watch: event log written by the runtime guard") { |v| @options[:file] = v }
        opts.on("--threshold MS", Integer, "watch: slow transaction threshold") { |v| @options[:threshold] = v }
        opts.on("--from-start", "watch: replay the existing log first") { @options[:from_start] = true }
        opts.on("-v", "--version", "print the version") { print_and_exit(VERSION) }
        opts.on("-h", "--help", "print this help") { print_and_exit(opts.to_s) }
      end
    end

    def list_rules
      Rules.all.each_value { |rule| @io.puts "#{rule.id.ljust(34)} #{rule.severity.to_s.ljust(7)} #{rule.remedy}" }
      exit EXIT_CLEAN
    end

    def print_and_exit(text)
      @io.puts text
      exit EXIT_CLEAN
    end
  end
end
