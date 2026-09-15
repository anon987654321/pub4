# frozen_string_literal: true

require "minitest/autorun"

ROOT = File.expand_path("..", __dir__) unless defined?(ROOT)
require_relative "../lib/cli/routing/model_catalog"

class TestModelCatalog < Minitest::Test
  def test_exact_id_wins
    id = Master::CLI::Routing::ModelCatalog.resolve(
      "ollama:qwen2.5-coder:7b",
      root: fixture_root
    )
    assert_equal "ollama:qwen2.5-coder:7b", id
  end

  def test_short_alias_resolves_when_unique
    id = Master::CLI::Routing::ModelCatalog.resolve(
      "qwen2.5-coder:7b",
      root: fixture_root
    )
    assert_equal "ollama:qwen2.5-coder:7b", id
  end

  def test_unknown_name_fails_before_dispatch
    error = assert_raises(ArgumentError) do
      Master::CLI::Routing::ModelCatalog.resolve("definitely-not-a-model", root: fixture_root)
    end
    assert_match(/unknown model/, error.message)
  end

  def test_local_alias_requires_a_local_model
    error = assert_raises(ArgumentError) do
      Master::CLI::Routing::ModelCatalog.resolve("ollama", root: fixture_root, local_models: [])
    end
    assert_match(/no local model/, error.message)
  end

  private

  def fixture_root
    @fixture_root ||= begin
      dir = Dir.mktmpdir("master-model-catalog")
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(
        File.join(dir, "data", "models.yml"),
        <<~YAML
          models:
            local:
              - id: ollama:qwen2.5-coder:7b
              - id: ollama:llama3.2:3b
            remote:
              - id: google/gemini-2.5-flash
        YAML
      )
      dir
    end
  end
end
