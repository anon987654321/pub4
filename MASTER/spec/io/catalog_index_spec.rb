# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../../lib/io/catalog_index"

class ProviderCatalogIndexSpec < Minitest::Test
  def with_index
    Dir.mktmpdir do |dir|
      yield Master::Io::CatalogIndex.new(db_path: File.join(dir, "catalog.sqlite3")), dir
    end
  end

  def test_imports_openrouter_models
    with_index do |index, dir|
      path = File.join(dir, "openrouter.json")
      File.write(path, JSON.generate({
        "data" => [{
          "id" => "openai/gpt-test",
          "name" => "GPT Test",
          "context_length" => 128_000,
          "pricing" => { "prompt" => "0.1", "completion" => "0.2" },
          "architecture" => { "input_modalities" => ["text"], "output_modalities" => ["text"], "tokenizer" => "test" },
        }],
      }))

      assert_equal 1, index.import_file("openrouter", path, normalizer: "openrouter")
      row = index.search("gpt-test").first
      assert_equal "openai/gpt-test", row["id"]
      assert_equal 128_000, row["context_length"]
    end
  end

  def test_imports_replicate_results_payload
    with_index do |index, dir|
      path = File.join(dir, "replicate.json")
      File.write(path, JSON.generate({
        "results" => [{
          "owner" => "black-forest-labs",
          "name" => "flux-schnell",
          "description" => "fast image model",
          "tags" => %w[image fast],
        }],
      }))

      assert_equal 1, index.import_file("replicate", path, normalizer: "replicate")
      row = index.search("flux", source: "replicate").first
      assert_equal "black-forest-labs/flux-schnell", row["id"]
      assert_match(/image/, row["tags"])
    end
  end

  def test_malformed_json_raises_cleanly
    with_index do |index, dir|
      path = File.join(dir, "bad.json")
      File.write(path, "{")
      assert_raises(JSON::ParserError) { index.import_file("replicate", path, normalizer: "replicate") }
    end
  end
end
