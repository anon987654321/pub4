# frozen_string_literal: true

require "fileutils"
require "time"
require "yaml"
require_relative "../../../lib/io/atomic_write"

module Replicate
  module SchemaSnapshot
    VERSION = 1
    DEFAULT_PATH = File.expand_path("../../data/schema_snapshot.yml", __dir__)

    module_function

    def write(client:, models:, path: DEFAULT_PATH, now: Time.now.utc)
      rows = Array(models).map do |model|
        keys = Array(client.input_keys(model)).map(&:to_s).uniq.sort
        raise "replicate: #{model} returned no input schema" if keys.empty?

        {
          "model" => model.to_s,
          "input_keys" => keys,
        }
      end

      rows = rows.sort_by { |row| row["model"] }
      document = {
        "schema" => VERSION,
        "provider" => "replicate",
        "source" => "replicate_api",
        "captured_at" => now.utc.iso8601,
        "models" => rows,
      }

      FileUtils.mkdir_p(File.dirname(path))
      writer = Object.new.extend(Master::Io::AtomicWrite)
      writer.write_atomic(path, YAML.dump(document))
      document
    end

    def read(path: DEFAULT_PATH)
      return nil unless File.file?(path)

      data = YAML.safe_load_file(path, aliases: false) || {}
      raise "replicate: schema snapshot version is unsupported" unless data["schema"].to_i == VERSION
      raise "replicate: schema snapshot has no captured_at" if data["captured_at"].to_s.strip.empty?
      raise "replicate: schema snapshot has no models" unless data["models"].is_a?(Array) && !data["models"].empty?

      data
    end

    def by_model(path: DEFAULT_PATH)
      snapshot = read(path:)
      return {} unless snapshot

      snapshot.fetch("models").to_h do |row|
        [row.fetch("model").to_s, Array(row["input_keys"]).map(&:to_s).sort]
      end
    end
  end
end
