# frozen_string_literal: true

class CreateSharedFoundationalTables < ActiveRecord::Migration[8.0]
  def up
    execute "CREATE VIRTUAL TABLE fts_idx USING fts5(model_type, content);"
    execute "CREATE TABLE system_audits (model_type TEXT, model_id INTEGER, delta_json TEXT, created_at DATETIME);"
    execute "CREATE TABLE transient_cache (cache_key TEXT PRIMARY KEY, cache_value TEXT, expires_at INTEGER);"
  end

  def down
    execute "DROP TABLE IF EXISTS fts_idx;"
    execute "DROP TABLE IF EXISTS system_audits;"
    execute "DROP TABLE IF EXISTS transient_cache;"
  end
end
