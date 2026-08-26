# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe "continuous integration output" do
  let(:offenses) do
    Txray.analyze(<<~RUBY, path: "app/models/order.rb")
      class Order < ApplicationRecord
        after_create :charge
        def charge = Faraday.post(url, fields: %w[a b], opts: { "x" => 1 })
      end
    RUBY
  end

  let(:result) { Txray::Result.new(offenses: offenses, files: [ "app/models/order.rb" ], skipped: []) }

  def annotation
    io = StringIO.new
    Txray::Reporters::Github.new(io: io, summary_path: nil).report(result)
    io.string.lines.first.chomp
  end

  describe "github annotations" do
    it "encodes a percent sign so the command is not misread" do
      body = annotation.split("::", 3).last
      expect(body).to include("%25w[a b]")
      expect(body).not_to match(/%(?!25|0A|0D)/)
    end

    it "folds the trace and the fix into the annotation body" do
      body = annotation.split("::", 3).last
      expect(body).to include("%0A")
      expect(body).to include("after_commit")
    end

    it "keeps property values free of the separators github parses on" do
      properties = annotation[/\A::\w+ (.*?)::/, 1]
      expect(properties).not_to include(":")
      expect(properties.split(",").size).to eq(4)
    end

    it "maps severity onto the levels github understands" do
      expect(annotation).to start_with("::error ")
      low = Txray::Offense.new(rule: Txray::Rules["cache-in-transaction"], path: "a.rb", line: 1, column: 1,
                               snippet: "Rails.cache.fetch", scope: offenses.first.scope, trace: [])
      io = StringIO.new
      Txray::Reporters::Github.new(io: io, summary_path: nil)
                              .report(Txray::Result.new(offenses: [ low ], files: [], skipped: []))
      expect(io.string).to start_with("::notice ")
    end

    it "writes a job summary when github provides one" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "summary.md")
        Txray::Reporters::Github.new(io: StringIO.new, summary_path: path).report(result)

        summary = File.read(path)
        expect(summary).to include("## txray", "**1 offenses**", "| Severity | Rule | Location |")
        expect(summary).to include("`http-in-transaction`", "`app/models/order.rb:3`")
      end
    end

    it "says so plainly when a clean run writes a summary" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "summary.md")
        clean = Txray::Result.new(offenses: [], files: [ "a.rb" ], skipped: [])
        Txray::Reporters::Github.new(io: StringIO.new, summary_path: path).report(clean)

        expect(File.read(path)).to include("No slow work found inside transactions across 1 files")
      end
    end

    it "escapes a pipe so the summary table survives" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "summary.md")
        piped = Txray.analyze(<<~RUBY, path: "a.rb")
          class Order < ApplicationRecord
            def settle
              transaction { rows.each { |row| row.save! } }
            end
          end
        RUBY
        Txray::Reporters::Github.new(io: StringIO.new, summary_path: path)
                                .report(Txray::Result.new(offenses: piped, files: [ "a.rb" ], skipped: []))

        table = File.read(path).lines.grep(/iteration-in-transaction/).first
        expect(table.scan(/(?<!\\)\|/).size).to eq(5)
      end
    end
  end

  describe "sarif" do
    def sarif(paths)
      io = StringIO.new
      Txray::Reporters::Sarif.new(io: io).report(Txray::Result.new(offenses: paths, files: [], skipped: []))
      JSON.parse(io.string)
    end

    it "declares every rule it reports so github can link them" do
      document = sarif(offenses)
      declared = document.dig("runs", 0, "tool", "driver", "rules").map { |rule| rule["id"] }
      reported = document.dig("runs", 0, "results").map { |result| result["ruleId"] }
      expect(reported - declared).to be_empty
    end

    it "uses only the levels code scanning accepts" do
      levels = sarif(offenses).dig("runs", 0, "results").map { |result| result["level"] }
      expect(levels - %w[note warning error]).to be_empty
    end
  end

  describe "paths" do
    it "reports paths relative to the working directory so github can find the file" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "app"))
        File.write(File.join(dir, "app", "order.rb"), <<~RUBY)
          class Order < ApplicationRecord
            after_create :charge
            def charge = Faraday.post(url)
          end
        RUBY

        Dir.chdir(dir) do
          scanned = Txray::Scanner.new(Txray::Config.new, paths: [ File.join(dir, "app") ]).run
          expect(scanned.offenses.first.path).to eq("app/order.rb")
        end
      end
    end
  end
end
