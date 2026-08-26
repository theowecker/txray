# frozen_string_literal: true

require "prism"

require_relative "txray/version"
require_relative "txray/error"
require_relative "txray/node_helpers"
require_relative "txray/catalog"
require_relative "txray/rule"
require_relative "txray/config"
require_relative "txray/offense"
require_relative "txray/source_file"
require_relative "txray/method_index"
require_relative "txray/transaction_scope"
require_relative "txray/classifier"
require_relative "txray/client_index"
require_relative "txray/analyzer"
require_relative "txray/scanner"
require_relative "txray/reporters"
require_relative "txray/runtime"
require_relative "txray/cli"

module Txray
  def self.scan(paths = nil, config: Config.load)
    Scanner.new(config, paths: paths).run
  end

  def self.analyze(code, path: "(string)", config: Config.new)
    source = SourceFile.parse(path, code: code) or return []
    Scanner.new(config).analyze([ source ]).sort_by(&:sort_key)
  end
end

require_relative "txray/railtie" if defined?(Rails::Railtie)
