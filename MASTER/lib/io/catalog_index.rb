# frozen_string_literal: true

# Indexes external model catalogs into ~/.master/provider_catalog.sqlite3.
#
# Adding a source: add an entry to SOURCES with url/kind/normalizer,
# implement normalize_<name> (or reuse one), refresh via
# MASTER/bin/provider-catalog or CatalogIndex#refresh. Built-ins:
# openrouter (llm_router), replicate (model_marketplace), replicate_github
# (github_model_index, URL from REPLICATE_MODELS_INDEX_URL). File imports
# use import_file(source_name, path, normalizer:).

require "fileutils"
require "json"
require "net/http"
require "sqlite3"
require "time"
require "uri"
require_relative "../boot/paths"

# Zeitwerk-ignored (see lib/master.rb's ignore list) and required directly by
# bin/provider-catalog, which doesn't load the full Master boot chain --
# ensure the Master namespace shell exists before reopening it below.
module Master; end

module Master::Io
  class CatalogIndex
    DEFAULT_DB = MasterPaths.state("provider_catalog.sqlite3")
    SOURCES = {
      "openrouter" => {
        url: "https://openrouter.ai/api/v1/models",
        kind: "llm_router",
        normalizer: "openrouter",
      },
      "replicate" => {
        url: "https://api.replicate.com/v1/models",
        kind: "model_marketplace",
        normalizer: "replicate",
      },
      "replicate_github" => {
        url: ENV["REPLICATE_MODELS_INDEX_URL"],
        kind: "github_model_index",
        normalizer: "replicate",
      },
    }.freeze

    def initialize(db_path: DEFAULT_DB)
      @db_path = db_path
      FileUtils.mkdir_p(File.dirname(db_path))
      migrate
    end

    def refresh(source_name, token: nil, url: nil)
      source = SOURCES.fetch(source_name)
      source_url = url || source.fetch(:url)
      if source_url.nil? || source_url.empty?
        raise "missing URL for #{source_name}; set REPLICATE_MODELS_INDEX_URL or pass --url"
      end

      payload = fetch_json(source_url, token:)
      upsert_snapshot(source: source_name, kind: source.fetch(:kind), url: source_url, payload:)
      rows = normalize(source.fetch(:normalizer), payload)
      replace_models(source_name, rows)
      rows.size
    end

    def import_file(source_name, path, normalizer: nil)
      source = SOURCES.fetch(source_name, { kind: "file_import", normalizer: normalizer || source_name })
      payload = JSON.parse(File.read(path))
      upsert_snapshot(source: source_name, kind: source.fetch(:kind), url: path, payload:)
      rows = normalize(source.fetch(:normalizer), payload)
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
      sql = <<~SQL.chomp
        SELECT source, id, name, description, context_length, input_modalities,
               output_modalities, price_prompt, price_completion, tags, updated_at
        FROM provider_models
      SQL
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
      create_provider_tables
      create_provider_indexes
    end

    def create_provider_tables
      create_provider_snapshots_table
      create_provider_models_table
    end

    def create_provider_snapshots_table
      db.execute_batch <<~SQL
        CREATE TABLE IF NOT EXISTS provider_snapshots (
          source TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          url TEXT NOT NULL,
          fetched_at TEXT NOT NULL,
          raw_json TEXT NOT NULL
        );
      SQL
    end

    def create_provider_models_table
      db.execute_batch <<~SQL
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
      SQL
    end

    def create_provider_indexes
      db.execute_batch <<~SQL
        CREATE INDEX IF NOT EXISTS idx_provider_models_source ON provider_models(source);
        CREATE INDEX IF NOT EXISTS idx_provider_models_name ON provider_models(name);
      SQL
    end

    def fetch_json(url, token: nil)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}" if token && !token.empty?
      request["Accept"] = "application/json"
      request["User-Agent"] = "MASTER provider catalog index"
      # Bounded so a slow or unreachable catalog endpoint can't hang the caller
      # (ROBUSTNESS: no unbounded HTTP). Tunable via env for slow networks.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: Integer(ENV.fetch("MASTER_HTTP_OPEN_TIMEOUT", "10")),
                                 read_timeout: Integer(ENV.fetch("MASTER_HTTP_READ_TIMEOUT", "30"))) do |http|
        http.request(request)
      end
      raise "#{url} returned #{response.code}: #{response.body[0, 200]}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    end

    def upsert_snapshot(source:, kind:, url:, payload:)
      db.execute(<<~SQL, [source, kind, url, Time.now.utc.iso8601, JSON.generate(payload)])
        INSERT INTO provider_snapshots(source, kind, url, fetched_at, raw_json)
        VALUES(?, ?, ?, ?, ?)
        ON CONFLICT(source) DO UPDATE SET
          kind=excluded.kind, url=excluded.url,
          fetched_at=excluded.fetched_at, raw_json=excluded.raw_json
      SQL
    end

    def replace_models(source, rows)
      db.transaction do
        db.execute("DELETE FROM provider_models WHERE source = ?", [source])
        rows.each do |row|
          db.execute(<<~SQL, [
            INSERT INTO provider_models(
              source, id, name, description, context_length,
              input_modalities, output_modalities,
              price_prompt, price_completion, tags, raw_json, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
            source, row.fetch(:id), row[:name], row[:description],
            row[:context_length], row[:input_modalities], row[:output_modalities],
            row[:price_prompt], row[:price_completion], row[:tags],
            JSON.generate(row[:raw]), Time.now.utc.iso8601
          ])
        end
      end
    end

    def normalize(kind, payload)
      case kind
      when "openrouter"
        Array(payload["data"]).map { |model| normalize_openrouter(model) }
      when "replicate"
        replicate_items(payload).map { |model| normalize_replicate(model) }
      else
        []
      end.compact
    end

    def replicate_items(payload)
      case payload
      when Array then payload
      when Hash
        payload["results"] || payload["data"] || payload["models"] || payload.values.find { |value| value.is_a?(Array) } || []
      else
        []
      end
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
        raw: model,
      }
    end

    def normalize_replicate(model)
      owner = model["owner"] || model.dig("user", "username") || model["namespace"]
      name = model["name"] || model["model_name"] || model["slug"]
      id = model["id"] || model["full_name"] || [owner, name].compact.join("/")
      return if id.nil? || id.empty?

      {
        id:,
        name: name || id,
        description: model["description"] || model["summary"],
        context_length: nil,
        input_modalities: Array(model["input_modalities"] || model["inputs"]).join(","),
        output_modalities: Array(model["output_modalities"] || model["outputs"]).join(","),
        price_prompt: nil,
        price_completion: nil,
        tags: Array(model["tags"] || model["categories"]).join(","),
        raw: model,
      }
    end
  end
end
