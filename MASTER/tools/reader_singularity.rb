# frozen_string_literal: true

# One data file, one loader. A second reader is a second implementation.
#
# lib/trace/why_explainer.rb held its own copy of the rule-shard merge loop,
# two directories from the real one in lib/boot/data.rb. The two agreed
# perfectly for as long as the shards existed. On 2026-08-12 the shards were
# folded into rules.yml, the copy's glob matched nothing, and it assigned {} over
# the real rules — silently emptying /why for all 225 rules. Nothing failed. The
# tests that caught it were testing /why, not the loader.
#
# `lint:data_singularity` already asserts one top-level key per data file. This
# is the same idea one level out: one *reader* per data file. Note the shape of
# the original defect — the copy called Master.load_yaml, the shared helper, so
# "bypasses the helper" would have missed it. What made it a second
# implementation was building the path and composing the result itself.
#
# 47 reader sites across 9 data files already exist, so this is a ratchet rather
# than a clean gate: the counts in data/reader_singularity.yml may fall and never
# rise, and a data file not listed there may have at most one reader.
#
#   ruby MASTER/tools/reader_singularity.rb
#   ruby MASTER/tools/reader_singularity.rb --json
#   ruby MASTER/tools/reader_singularity.rb --ratchet   # record a new low
#
# Wired as `rake lint:reader_singularity`, pinned by test/test_reader_singularity.rb.

require "json"
require "yaml"

module Pub4
  class ReaderSingularity
    ROOT = File.expand_path("../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    CEILINGS = File.join(MASTER, "data", "reader_singularity.yml")

    # First-party Ruby that may legitimately read MASTER's data.
    TREES = ["MASTER/lib", "MASTER/tools", "OPENBSD/tools"].freeze

    LOAD = /(?:YAML\.(?:safe_)?load_file|YAML\.(?:safe_)?load\b|load_yaml\s*\(|safe_load_file)/

    # The load call and the filename routinely land on different lines:
    #   path = File.join(Master::DATA, "voice.yml")
    #   data = Master.load_yaml(path)
    # so a filename anywhere in the preceding few lines counts as the argument.
    WINDOW = 5

    def self.data_files
      @data_files ||= Dir.glob(File.join(MASTER, "data", "**", "*.yml")).map { |path| File.basename(path) }.uniq
    end

    def self.sources
      @sources ||= TREES.flat_map { |tree| Dir.glob(File.join(ROOT, tree, "**", "*.rb")) }.sort
    end

    # data file => the Ruby files that load it.
    def self.readers
      @readers ||= begin
        found = Hash.new { |hash, key| hash[key] = [] }
        sources.each { |path| scan(path, found) }
        found.each_value(&:uniq!)
        found
      end
    end

    def self.scan(path, found)
      lines = File.readlines(path)
      relative = path.sub("#{ROOT}/", "")
      lines.each_with_index do |line, index|
        next if line.match?(/\A\s*#/) || !line.match?(LOAD)

        window = lines[[0, index - WINDOW].max..index].join
        data_files.each { |name| found[name] << relative if window.include?(%("#{name}")) }
      end
    end

    def self.ceilings
      @ceilings ||= YAML.safe_load_file(CEILINGS).fetch("reader_singularity").fetch("ceiling") || {}
    end

    def self.run
      findings = readers.filter_map do |name, files|
        ceiling = ceilings.fetch(name, 1)
        next if files.size <= ceiling

        { "data" => name, "readers" => files.size, "ceiling" => ceiling, "files" => files }
      end

      { "checked" => sources.size, "loaded" => readers.size,
        "current" => readers.transform_values(&:size).select { |_, n| n > 1 }.sort.to_h,
        "findings" => findings }
    end

    # Only ever down, per file: the minimum of what is recorded and what is
    # measured. A writer that took today's counts whatever they were made a
    # --ratchet run aimed at one file's slack raise another's ceiling and
    # launder new debt into the baseline — rules.yml 10 to 11, 2026-08-31.
    # Per file, the minimum of what is recorded and what is measured.
    def self.ratchet!
      current = readers.transform_values(&:size).select { |_, count| count > 1 }.sort.to_h
      recorded = ceilings
      refused = current.select { |name, count| recorded.key?(name) && count > recorded[name] }
      lows = current.to_h { |name, count| [name, recorded.key?(name) ? [count, recorded[name]].min : count] }

      body = YAML.safe_load_file(CEILINGS)
      body["reader_singularity"]["ceiling"] = lows
      header = File.read(CEILINGS).split(/^reader_singularity:/).first
      File.write(CEILINGS, header + YAML.dump(body).sub(/\A---\n/, ""))
      [lows, refused]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.include?("--ratchet")
    lows, refused = Pub4::ReaderSingularity.ratchet!
    puts "reader_singularity: recorded #{lows.size} multi-reader file(s), #{lows.values.sum} sites"
    # Named, not swallowed: a refusal is the ratchet holding, and the file it
    # held for is the one that just gained a reader.
    refused.each do |name, count|
      puts "reader_singularity: held #{name} at #{lows[name]} — measured #{count}, which would have been a raise"
    end
    exit 0
  end

  report = Pub4::ReaderSingularity.run

  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    report["findings"].each do |row|
      puts "#{row['data']}: #{row['readers']} readers (ceiling #{row['ceiling']})"
      row["files"].each { |file| puts "  #{file}" }
    end
    puts
    sites = report["current"].values.sum
    puts "#{report['checked']} source files checked, #{report['loaded']} data files loaded, " \
         "#{report['current'].size} with more than one reader (#{sites} sites)"
    puts "reader_singularity: #{report['findings'].empty? ? 'clean' : "#{report['findings'].size} over ceiling"}"
  end

  exit(report["findings"].empty? ? 0 : 1)
end
