# frozen_string_literal: true

require "json"
require "net/http"
require "sqlite3"
require "time"
require "uri"
require_relative "../master_paths"

module Providers
  class CatalogIndex
    DEFAULT_DB = MasterPaths.state("provider_catalog.sqlite3")
    SOURCES = {
      "openrouter" => {
        url: "https://openrouter.ai/api/v1/models",
        kind: "llm_router"
      },
      "replicate" => {
        url: "https://api.replicate.com/v1/models",
        kind: "model_marketplace"
      }
    }.freeze

    def initialize(db_path: DEFAULT_DB)
      @db_path = db_path
      FileUtils.mkdir_p(File.dirname(db_path))
      migrate
    end

    def refresh(source_name, token: nil)
      source = SOURCES.fetch(source_name)
      payload = fetch_json(source.fetch(:url), token: token)
      upsert_snapshot(source_name, source.fetch(:kind), source.fetch(:url), payload)
      rows = normalize(source_name, payload)
      replace_models(source_name, rows)
      rows.size
    end

    def search(query = nil, source: nil, limit: 50)
      clauses = []
      params = []
      if source
        clauses << "source = ?"
        params << source
      end
      if query && !query.empty?
        clauses << "(id LIKE ? OR name LIKE ? OR description LIKE ? OR tags LIKE ?)"
        4.times { params << "%#{query}%" }
      end
      sql = "SELECT source, id, name, description, context_length, input_modalities, output_modalities, price_prompt, price_completion, tags, updated_at FROM provider_models"
      sql += " WHERE #{clauses.join(" AND ")}" unless clauses.empty?
      sql += " ORDER BY source, id LIMIT ?"
      params << limit
      db.execute(sql, params)
    end

    private

    attr_reader :db_path

    def db
      @db ||= SQLite3::Database.new(db_path).tap { |database| database.results_as_hash = true }
    end

    def migrate
      db.execute_batch <<~SQL
        CREATE TABLE IF NOT EXISTS provider_snapshots (
          source TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          url TEXT NOT NULL,
          fetched_at TEXT NOT NULL,
          raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS provider_models (
          source TEXT NOT NULL,
          id TEXT NOT NULL,
          name TEXT,
          description TEXT,
          context_length INTEGER,
          input_modalities TEXT,
          output_modalities TEXT,
          price_prompt REAL,
          price_completion REAL,
          tags TEXT,
          raw_json TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (source, id)
        );

        CREATE INDEX IF NOT EXISTS idx_provider_models_source ON provider_models(source);
        CREATE INDEX IF NOT EXISTS idx_provider_models_name ON provider_models(name);
      SQL
    end

    def fetch_json(url, token: nil)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}" if token && !token.empty?
      request["User-Agent"] = "MASTER provider catalog index"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
      raise "#{url} returned #{response.code}: #{response.body[0, 200]}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    end

    def upsert_snapshot(source, kind, url, payload)
      db.execute(
        "INSERT INTO provider_snapshots(source, kind, url, fetched_at, raw_json) VALUES(?, ?, ?, ?, ?) ON CONFLICT(source) DO UPDATE SET kind=excluded.kind, url=excluded.url, fetched_at=excluded.fetched_at, raw_json=excluded.raw_json",
        [source, kind, url, Time.now.utc.iso8601, JSON.generate(payload)]
      )
    end

    def replace_models(source, rows)
      db.transaction do
        db.execute("DELETE FROM provider_models WHERE source = ?", [source])
        rows.each do |row|
          db.execute(
            "INSERT INTO provider_models(source, id, name, description, context_length, input_modalities, output_modalities, price_prompt, price_completion, tags, raw_json, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [source, row.fetch(:id), row[:name], row[:description], row[:context_length], row[:input_modalities], row[:output_modalities], row[:price_prompt], row[:price_completion], row[:tags], JSON.generate(row[:raw]), Time.now.utc.iso8601]
          )
        end
      end
    end

    def normalize(source, payload)
      case source
      when "openrouter"
        Array(payload["data"]).map { |model| normalize_openrouter(model) }
      when "replicate"
        Array(payload["results"] || payload["data"]).map { |model| normalize_replicate(model) }
      else
        []
      end.compact
    end

    def normalize_openrouter(model)
      pricing = model["pricing"] || {}
      architecture = model["architecture"] || {}
      {
        id: model["id"],
        name: model["name"] || model["id"],
        description: model["description"],
        context_length: model["context_length"],
        input_modalities: Array(architecture["input_modalities"]).join(","),
        output_modalities: Array(architecture["output_modalities"]).join(","),
        price_prompt: pricing["prompt"].to_f,
        price_completion: pricing["completion"].to_f,
        tags: [architecture["modality"], architecture["tokenizer"], model["top_provider"]&.dig("context_length")].compact.join(","),
        raw: model
      }
    end

    def normalize_replicate(model)
      owner = model["owner"]
      name = model["name"]
      {
        id: [owner, name].compact.join("/"),
        name: name,
        description: model["description"],
        context_length: nil,
        input_modalities: "",
        output_modalities: "",
        price_prompt: nil,
        price_completion: nil,
        tags: Array(model["tags"]).join(","),
        raw: model
      }
    end
  end
end
