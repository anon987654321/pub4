# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require "set"

DATA = File.expand_path("../data", __dir__)

YAML_SPECS = {
  "attention_context.yml"           => { required_keys: %w[protocol fields rendering when_to_emit], arrays: [] },
  "mobile_web_opportunities.yml"    => { required_keys: %w[clusters mining_queries],               arrays: %w[clusters] },
  "prompt_archaeology_patterns.yml" => { required_keys: %w[policy clusters orchestration_blueprint risk_tiers], arrays: %w[clusters] },
  "visual_clusters.yml"             => { required_keys: %w[clusters],                              arrays: %w[clusters] },
  "repo_topic_clusters.yml"         => { required_keys: %w[clusters],                              arrays: %w[clusters] }
}.freeze

class TestYamlRegistries < Minitest::Test
  YAML_SPECS.each do |filename, spec|
    define_method(:"test_#{filename.tr('.', '_')}_parses") do
      path = File.join(DATA, filename)
      assert File.exist?(path), "#{filename} missing"
      data = YAML.load_file(path)
      assert_kind_of Hash, data, "#{filename} root must be a Hash"
    end

    define_method(:"test_#{filename.tr('.', '_')}_required_keys") do
      data = YAML.load_file(File.join(DATA, filename))
      spec[:required_keys].each do |key|
        assert data.key?(key), "#{filename} missing top-level key: #{key}"
      end
    end

    define_method(:"test_#{filename.tr('.', '_')}_arrays_non_empty") do
      data = YAML.load_file(File.join(DATA, filename))
      spec[:arrays].each do |key|
        next unless data.key?(key)
        val = data[key]
        assert val.is_a?(Array) && val.any?, "#{filename}[#{key}] must be a non-empty array"
      end
    end
  end
end

class TestClusterConsistency < Minitest::Test
  CLUSTER_FILES = %w[visual_clusters.yml repo_topic_clusters.yml mobile_web_opportunities.yml].freeze

  CLUSTER_FILES.each do |filename|
    define_method(:"test_#{filename.tr('.', '_')}_no_duplicate_ids") do
      data  = YAML.load_file(File.join(DATA, filename))
      items = Array(data["clusters"])
      ids   = items.map { |c| c["id"] || c["name"] }.compact
      dups  = ids.tally.select { |_, n| n > 1 }.keys
      assert dups.empty?, "#{filename} has duplicate cluster ids: #{dups.join(', ')}"
    end
  end
end
