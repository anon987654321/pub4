# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require "set"

DATA = File.expand_path("../data", __dir__)

YAML_SPECS = {
  "attention_context.yml"        => { required_keys: %w[protocol fields rendering when_to_emit], arrays: [] },
  "mobile_web_opportunities.yml" => { required_keys: %w[clusters mining_queries],                arrays: %w[clusters] },
  "visual_clusters.yml"          => { required_keys: %w[clusters],                                arrays: %w[clusters] },
  "patterns.yml"                 => { required_keys: %w[gh openbsd zsh infer prompt_archaeology repo_topics], arrays: [] }
}.freeze

PATTERNS_NAMESPACES = {
  "infer"              => %w[commands],
  "prompt_archaeology" => %w[policy clusters orchestration_blueprint risk_tiers],
  "repo_topics"        => %w[clusters]
}.freeze

DELETED_FILES = %w[infer_patterns.yml prompt_archaeology_patterns.yml repo_topic_clusters.yml].freeze

class TestYamlRegistries < Minitest::Test
  YAML_SPECS.each do |filename, spec|
    define_method(:"test_#{filename.tr('.', '_')}_parses") do
      path = File.join(DATA, filename)
      assert File.exist?(path), "#{filename} missing"
      data = YAML.load_file(path, aliases: true)
      assert_kind_of Hash, data, "#{filename} root must be a Hash"
    end

    define_method(:"test_#{filename.tr('.', '_')}_required_keys") do
      data = YAML.load_file(File.join(DATA, filename), aliases: true)
      spec[:required_keys].each do |key|
        assert data.key?(key), "#{filename} missing top-level key: #{key}"
      end
    end

    define_method(:"test_#{filename.tr('.', '_')}_arrays_non_empty") do
      data = YAML.load_file(File.join(DATA, filename), aliases: true)
      spec[:arrays].each do |key|
        next unless data.key?(key)
        val = data[key]
        assert val.is_a?(Array) && val.any?, "#{filename}[#{key}] must be a non-empty array"
      end
    end
  end
end

class TestPatternsNamespaces < Minitest::Test
  PATTERNS_NAMESPACES.each do |namespace, inner_keys|
    define_method(:"test_patterns_#{namespace}_namespace_populated") do
      data = YAML.load_file(File.join(DATA, "patterns.yml"), aliases: true)
      ns = data[namespace]
      assert_kind_of Hash, ns, "patterns.yml[#{namespace}] must be a Hash"
      inner_keys.each do |key|
        assert ns.key?(key), "patterns.yml[#{namespace}] missing key: #{key}"
      end
    end
  end
end

class TestDeletedFilesAbsent < Minitest::Test
  DELETED_FILES.each do |filename|
    define_method(:"test_#{filename.tr('.', '_')}_removed") do
      refute File.exist?(File.join(DATA, filename)),
             "#{filename} should be removed — content merged into patterns.yml"
    end
  end
end

class TestRulesYamlRegistry < Minitest::Test
  REQUIRED_RULE_FIELDS = %w[id name tier severity autofix].freeze

  def test_rules_yml_has_no_duplicate_rule_ids
    ids = rules.map { |rule| rule["id"] }.compact
    duplicates = ids.tally.select { |_, count| count > 1 }.keys

    assert duplicates.empty?, "rules.yml has duplicate rule ids: #{duplicates.join(', ')}"
  end

  def test_rules_yml_entries_have_required_fields
    missing = rules.filter_map do |rule|
      absent = REQUIRED_RULE_FIELDS.reject { |field| rule.key?(field) }
      "#{rule['id'] || '<missing id>'}: #{absent.join(', ')}" if absent.any?
    end

    assert missing.empty?, "rules.yml entries missing required fields: #{missing.join('; ')}"
  end

  private

  def rules
    data = YAML.load_file(File.join(DATA, "rules.yml"), aliases: true)
    data.fetch("rules").values.flat_map { |entries| Array(entries) }
  end
end

class TestClusterConsistency < Minitest::Test
  CLUSTER_FILES = %w[visual_clusters.yml mobile_web_opportunities.yml].freeze

  CLUSTER_FILES.each do |filename|
    define_method(:"test_#{filename.tr('.', '_')}_no_duplicate_ids") do
      data  = YAML.load_file(File.join(DATA, filename), aliases: true)
      items = Array(data["clusters"])
      ids   = items.map { |c| c["id"] || c["name"] }.compact
      dups  = ids.tally.select { |_, n| n > 1 }.keys
      assert dups.empty?, "#{filename} has duplicate cluster ids: #{dups.join(', ')}"
    end
  end

  def test_patterns_repo_topics_no_duplicate_ids
    data  = YAML.load_file(File.join(DATA, "patterns.yml"), aliases: true)
    items = Array(data.dig("repo_topics", "clusters"))
    ids   = items.map { |c| c["id"] || c["name"] }.compact
    dups  = ids.tally.select { |_, n| n > 1 }.keys
    assert dups.empty?, "patterns.yml[repo_topics][clusters] has duplicate ids: #{dups.join(', ')}"
  end

  def test_patterns_prompt_archaeology_no_duplicate_ids
    data  = YAML.load_file(File.join(DATA, "patterns.yml"), aliases: true)
    items = Array(data.dig("prompt_archaeology", "clusters"))
    ids   = items.map { |c| c["id"] || c["name"] }.compact
    dups  = ids.tally.select { |_, n| n > 1 }.keys
    assert dups.empty?, "patterns.yml[prompt_archaeology][clusters] has duplicate ids: #{dups.join(', ')}"
  end
end
