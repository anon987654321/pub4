# frozen_string_literal: true

require_relative "test_helper"

class TestLawVocabulary < Minitest::Test
  ROOTS = %w[lib law bin tools].freeze
  FORBIDDEN = [
    /\bRuleFactory\b/,
    /\bRuleHealth\b/,
    /\bRuleDSL\b/,
    /Review::Scan::Rule\b/,
    /Review::Scan::Rules\b/,
    /\bscanner\.rules\b/,
    /\bLaw\.rules\b/,
    /\bRule\s*=\s*Law\b/,
    /<\s*Rule\b/,
  ].freeze

  def files
    ROOTS.flat_map do |root|
      Dir.glob(File.join(Master::ROOT, root, "**", "*")).select { |path| File.file?(path) }
    end.reject { |path| path.include?("/vendor/") || path.include?("/node_modules/") }
  end

  def test_runtime_uses_law_vocabulary
    offenders = files.filter_map do |path|
      source = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
      matches = FORBIDDEN.filter_map { |pattern| pattern.source if source.match?(pattern) }
      matches.empty? ? nil : "#{path.delete_prefix("#{Master::ROOT}/")}: #{matches.join(", ")}"
    end

    assert_empty offenders, "obsolete Rule vocabulary remains:\n#{offenders.join("\n")}"
  end

  def test_scanner_exposes_laws_not_rules
    scanner = Master::Fix::Scanner.build(root: Master::ROOT)
    assert_respond_to scanner, :laws
    refute_respond_to scanner, :rules
  end
end
