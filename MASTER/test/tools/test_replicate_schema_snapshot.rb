# frozen_string_literal: true

require_relative "tools_helper"
require_relative "../../tools/replicate/lib/schema_snapshot"
require "tmpdir"
require "time"

class TestReplicateSchemaSnapshot < Minitest::Test
  class Client
    def initialize(rows) = @rows = rows
    def input_keys(model) = @rows.fetch(model)
  end

  def test_write_sorts_and_deduplicates_provider_input_keys
    Dir.mktmpdir do |dir|
      path = File.join(dir, "schema_snapshot.yml")
      now = Time.utc(2026, 9, 28, 14, 30, 0)
      client = Client.new(
        "acme/one" => %w[seed prompt seed output_format],
        "acme/two" => %w[input_images prompt],
      )

      document = Replicate::SchemaSnapshot.write(
        client:,
        models: %w[acme/two acme/one],
        path:,
        now:,
      )

      assert_equal 1, document["schema"]
      assert_equal "replicate_api", document["source"]
      assert_equal "2026-09-28T14:30:00Z", document["captured_at"]
      assert_equal(
        [
          {"model" => "acme/one", "input_keys" => %w[output_format prompt seed]},
          {"model" => "acme/two", "input_keys" => %w[input_images prompt]},
        ],
        document["models"],
      )
      assert_equal document, Replicate::SchemaSnapshot.read(path:)
      assert_equal(
        {
          "acme/one" => %w[output_format prompt seed],
          "acme/two" => %w[input_images prompt],
        },
        Replicate::SchemaSnapshot.by_model(path:),
      )
    end
  end

  def test_write_refuses_a_model_with_no_schema_keys
    Dir.mktmpdir do |dir|
      client = Client.new("acme/empty" => [])

      error = assert_raises(RuntimeError) do
        Replicate::SchemaSnapshot.write(
          client:,
          models: ["acme/empty"],
          path: File.join(dir, "schema_snapshot.yml"),
        )
      end

      assert_match(/returned no input schema/, error.message)
    end
  end

  def test_read_refuses_an_unsupported_snapshot_version
    Dir.mktmpdir do |dir|
      path = File.join(dir, "schema_snapshot.yml")
      File.write(path, YAML.dump(
        "schema" => 99,
        "provider" => "replicate",
        "source" => "replicate_api",
        "captured_at" => Time.now.utc.iso8601,
        "models" => [{"model" => "acme/one", "input_keys" => ["prompt"]}],
      ))

      assert_raises(RuntimeError) { Replicate::SchemaSnapshot.read(path:) }
    end
  end
end
