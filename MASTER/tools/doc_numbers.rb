# frozen_string_literal: true

# A dimension written in prose is a second source of truth for a number the
# tokens already own.
#
# A document prescribing an 8px step while design_tokens.yml defines space_sm as
# 0.75rem gives the tree two spacing scales, and the gates read different ones.
#
# Mentioning a value is fine. Prescribing one without saying where it comes from
# is what drifts, because the reader has no way to find the value that governs.
# A paragraph passes when it names the source -- the tokens file, the stylesheet,
# or the token key itself.
#
#   ruby MASTER/tools/doc_numbers.rb
#   ruby MASTER/tools/doc_numbers.rb --json

require "json"
require "yaml"

module Pub4
  class DocNumbers
    ROOT = File.expand_path("../..", __dir__)
    TOKENS = File.join(ROOT, "RAILS/shared/design_tokens.yml")
    TREES = %w[MASTER RAILS OPENBSD].freeze
    SKIP = %r{/(node_modules|vendor|knowledge|output|tmp|\.master)/}

    # Naming any of these makes the number traceable.
    SOURCES = %w[design_tokens.yml _dialect_tokens.scss tokens.css design_tokens].freeze

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
        walk.call(YAML.safe_load_file(TOKENS), [])
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
  report = Pub4::DocNumbers.run
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
end
