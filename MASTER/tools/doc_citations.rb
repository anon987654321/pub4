# frozen_string_literal: true

# Prose that quotes a number data/ owns must quote the number data/ holds.
#
# TODO.md carried a copy of data/spine.yml's raise log — "38,294, allowance 1 of
# 2" — while spine.yml had ratcheted to 38,285 and cleared the log. Two sources,
# one drifted, which is the failure that register describes in its own words two
# sections further down. Within a day of it being fixed, DECISIONS.md was left
# claiming a rebaseline to 38823 against spine.yml's 38811. Nothing parses prose,
# so nothing noticed either time.
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

module Pub4
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
  report = Pub4::DocCitations.run

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
