# frozen_string_literal: true

# Prose that quotes a number data/ owns must quote the number data/ holds.
#
# A document that copies a figure out of data/ is a second source, and nothing
# parses prose, so the copy drifts unnoticed the first time the data moves.
#
# Two forms are checked, and neither needs a document rewritten to adopt it:
#
#   1. A quotation. Documents here already write `core_files: 6` and
#      `consecutive_raises_allowed: 2` — key and value together. When the key is a
#      distinctive numeric key that data/ defines, the value must match. Six such
#      quotations existed when this landed and all six were correct; the point is
#      that the seventh cannot silently stop being.
#
#   2. A citation, for a number quoted without its key:
#
#        rebaselined 38285 → 38811 <!-- cite: data/spine.yml#spine.lib_code_ceiling -->
#
#      The last number before the marker must equal the value at that key. A
#      marker naming a file or key that does not resolve fails too, so a citation
#      cannot outlive the thing it cites.
#
#   ruby MASTER/tools/doc_citations.rb
#   ruby MASTER/tools/doc_citations.rb --json
#
# Wired as `rake lint:doc_citations`, pinned by test/test_doc_citations.rb.

require "json"
require "yaml"

module Operator
  class DocCitations
    ROOT = File.expand_path("../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    TREES = %w[MASTER RAILS OPENBSD].freeze
    SKIP = %r{/(node_modules|vendor|knowledge|output|tmp|\.master|\.git)/}

    CITE = /<!--\s*cite:\s*([^\s#]+)#([^\s]+)\s*-->/
    NUMBER = /(-?\d[\d,_]*(?:\.\d+)?)(?!.*\d)/m

    # A key generic enough to appear in prose by accident says nothing. Keys that
    # are compound, long, and hold a number or a flag are the ones a document
    # quotes on purpose.
    def self.distinctive?(key, values)
      key.include?("_") && key.length >= 8 &&
        values.all? { |value| value.is_a?(Numeric) || [true, false].include?(value) }
    end

    # leaf key => every value data/ gives it. Same key in two files with two
    # values is legitimate (different registries), so a quotation matching any
    # of them passes; what fails is matching none.
    def self.keys
      @keys ||= begin
        found = Hash.new { |hash, key| hash[key] = [] }
        Dir.glob(File.join(MASTER, "data", "*.yml")).sort.each do |path|
          collect(safe_load(path), [], found)
        end
        found.select { |key, values| distinctive?(key, values) }
             .transform_values { |values| values.map(&:to_s).uniq }
      end
    end

    def self.collect(node, path, found)
      case node
      when Hash then node.each { |key, value| collect(value, path + [key.to_s], found) }
      when Array then nil
      else found[path.last] << node unless path.empty?
      end
    end

    def self.safe_load(path)
      YAML.safe_load_file(path, aliases: true) || {}
    rescue Psych::Exception
      {}
    end

    def self.docs
      @docs ||= TREES.flat_map { |tree| Dir[File.join(ROOT, tree, "**", "*.md")] }
                     .reject { |path| path =~ SKIP }
                     .map { |path| path.sub("#{ROOT}/", "") }
                     .sort
    end

    # Resolve data/spine.yml#spine.lib_code_ceiling against the repo root, then
    # against MASTER/, so both spellings work.
    def self.resolve(file, key)
      path = [File.join(ROOT, file), File.join(MASTER, file)].find { |candidate| File.exist?(candidate) }
      return [nil, "no such file"] unless path

      value = key.split(".").reduce(safe_load(path)) { |node, part| node.is_a?(Hash) ? node[part] : nil }
      value.nil? ? [nil, "no such key"] : [value.to_s, nil]
    end

    def self.run
      findings = []
      quotations = 0
      citations = 0

      docs.each do |doc|
        body = File.read(File.join(ROOT, doc))
        next if body.include?("<!-- doc_citations: ignore -->")

        quotations += check_quotations(doc, body, findings)
        citations += check_citations(doc, body, findings)
      end

      { "docs" => docs.size, "quotations" => quotations, "citations" => citations, "findings" => findings }
    end

    def self.check_quotations(doc, body, findings)
      count = 0
      keys.each do |key, values|
        body.scan(/#{Regexp.escape(key)}:\s*(-?[\d.]+|true|false)/) do
          count += 1
          quoted = Regexp.last_match(1)
          next if values.include?(quoted)

          findings << { "doc" => doc, "kind" => "quotation", "key" => key, "quoted" => quoted,
                        "actual" => values.join(" / "),
                        "message" => "quotes #{key}: #{quoted}; data/ holds #{values.join(' / ')}" }
        end
      end
      count
    end

    def self.check_citations(doc, body, findings)
      count = 0
      body.each_line.with_index(1) do |line, number|
        line.scan(CITE) do
          count += 1
          file, key = Regexp.last_match(1), Regexp.last_match(2)
          before = line.split(/<!--\s*cite:/).first.to_s
          findings.concat(citation_findings(doc, number, file, key, before))
        end
      end
      count
    end

    def self.citation_findings(doc, number, file, key, before)
      actual, error = resolve(file, key)
      base = { "doc" => doc, "kind" => "citation", "key" => "#{file}##{key}", "line" => number }
      return [base.merge("message" => "cites #{file}##{key}, which does not resolve (#{error})")] if error

      quoted = before[NUMBER, 1]
      return [base.merge("message" => "citation has no number before it")] unless quoted
      return [] if quoted.delete(",_") == actual

      [base.merge("quoted" => quoted, "actual" => actual,
                  "message" => "cites #{key} as #{quoted}; data/ holds #{actual}")]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = Operator::DocCitations.run

  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    report["findings"].each { |row| puts "#{row['doc']}#{row['line'] ? ":#{row['line']}" : ''}: #{row['message']}" }
    puts
    puts "#{report['docs']} documents, #{report['quotations']} quotation(s) and " \
         "#{report['citations']} citation(s) checked against data/"
    puts "doc_citations: #{report['findings'].empty? ? 'clean' : "#{report['findings'].size} drifted"}"
  end

  exit(report["findings"].empty? ? 0 : 1)
end


# frozen_string_literal: true

# A dimension written in prose is a second source of truth for a number the
# MASTER's canonical design system already owns.
#
# A document prescribing an 8px step while the canonical design system defines
# space_sm as 0.75rem gives the tree two spacing scales, and the gates read different ones.
#
# Mentioning a value is fine. Prescribing one without saying where it comes from
# is what drifts, because the reader has no way to find the value that governs.
# A paragraph passes when it names the source -- the canonical design system, the stylesheet,
# or the token key itself.
#
#   ruby MASTER/tools/doc_numbers.rb
#   ruby MASTER/tools/doc_numbers.rb --json

require "json"
require "yaml"

module Operator
  class DocNumbers
    ROOT = File.expand_path("../..", __dir__)
    RULES = File.join(ROOT, "MASTER/data/rules.yml")
    TREES = %w[MASTER RAILS OPENBSD].freeze
    SKIP = %r{/(node_modules|vendor|knowledge|output|tmp|\.master)/}

    # Naming any of these makes the number traceable.
    SOURCES = %w[MASTER/data/rules.yml _dialect_tokens.scss tokens.css design_system].freeze

    # Values so generic that a match says nothing about design tokens. 8px and
    # 4px are the rhythm itself and appear in prose about the rhythm; 1rem is the
    # browser default. Flagging them produces noise, not drift.
    IGNORE = %w[1rem 4px 8px 16px 12px].freeze

    def self.tokens
      @tokens ||= begin
        values = {}
        walk = lambda do |node, path|
          case node
          when Hash then node.each { |key, value| walk.call(value, path + [key.to_s]) }
          when Array then node.each { |value| walk.call(value, path) }
          else
            text = node.to_s
            (values[text] ||= []) << path.join(".") if text.match?(/\A-?[\d.]+(px|rem|em)\z/)
          end
        end
        document = YAML.safe_load_file(RULES, aliases: true) || {}
        walk.call(document.fetch("design_system", {}), [])
        values.reject { |value, _| IGNORE.include?(value) }
      end
    end

    def self.docs
      TREES.flat_map { |tree| Dir[File.join(ROOT, tree, "**", "*.md")] }
           .reject { |path| path =~ SKIP }
           .map { |path| path.sub("#{ROOT}/", "") }
           .sort
    end

    # The paragraph names where the number lives: the tokens file, a stylesheet,
    # or a token key (tap_min, space_sm, feed_max).
    def self.traceable?(paragraph, keys)
      return true if SOURCES.any? { |source| paragraph.include?(source) }

      # The tokens file writes tap_min; a stylesheet and the documents that
      # quote it write --tap-min. Same source, two spellings.
      normalized = paragraph.tr("-", "_")
      keys.any? do |key|
        leaf = key.split(".").last.tr("-", "_")
        normalized.include?(leaf)
      end
    end

    def self.run
      findings = Hash.new { |hash, key| hash[key] = [] }

      docs.each do |doc|
        body = File.read(File.join(ROOT, doc))
        next if body.include?("<!-- doc_numbers: ignore -->")

        paragraphs = body.split(/\n{2,}/)
        tokens.each do |value, keys|
          pattern = /(?<![\w.-])#{Regexp.escape(value)}(?![\w-])/
          mentions = paragraphs.select { |paragraph| paragraph.match?(pattern) }
          next if mentions.empty?
          next if mentions.all? { |paragraph| traceable?(paragraph, keys) }

          findings[doc] << { "value" => value, "tokens" => keys.uniq.first(3) }
        end
      end

      { docs: docs.size, values: tokens.size, findings: findings.sort.to_h }
    end
  end
end


if $PROGRAM_NAME == __FILE__
  if ARGV.delete("--numbers")
    report = Operator::DocNumbers.run
    count = report[:findings].values.sum(&:size)
    if ARGV.include?("--json")
      puts JSON.pretty_generate(report)
    else
      report[:findings].each do |doc, rows|
        puts doc
        rows.each { |row| puts "  #{row['value'].ljust(9)} owned by #{row['tokens'].join(', ')}" }
      end
      puts
      puts "#{report[:values]} token values checked across #{report[:docs]} documents, #{count} untraceable"
    end
    exit(count.zero? ? 0 : 1)
  else
    report = Operator::DocCitations.run
    if ARGV.include?("--json")
      puts JSON.pretty_generate(report)
    else
      puts JSON.pretty_generate(report)
    end
    exit(report.fetch("findings").empty? ? 0 : 1)
  end
end
