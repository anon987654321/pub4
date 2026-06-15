#!/usr/bin/env ruby
# frozen_string_literal: true

require "sqlite3"
require "json"

module Repligen
  Model = Struct.new(:id, :owner, :name, :description, :type, :cost, :runs, :url, keyword_init: true)

  class Database
    attr_reader :db

    def initialize(path = "repligen.db")
      @db = SQLite3::Database.new(path)

      @db.results_as_hash = true

      setup_schema

    end

    def setup_schema
      @db.execute_batch <<-SQL

        CREATE TABLE IF NOT EXISTS models (

          id TEXT PRIMARY KEY,

          owner TEXT NOT NULL,

          name TEXT NOT NULL,

          description TEXT,

          type TEXT,

          cost REAL DEFAULT 0.05,

          runs INTEGER DEFAULT 0,

          url TEXT,

          synced_at INTEGER

        );

        CREATE INDEX IF NOT EXISTS idx_type ON models(type);
        CREATE INDEX IF NOT EXISTS idx_owner ON models(owner);

      SQL

    end

    def save(model)
      @db.execute(<<-SQL, model.to_h.values_at(:id, :owner, :name, :description, :type, :cost, :runs, :url))

        INSERT OR REPLACE INTO models (id, owner, name, description, type, cost, runs, url, synced_at)

        VALUES (?, ?, ?, ?, ?, ?, ?, ?, #{Time.now.to_i})

      SQL

    end

    def by_type(type, limit = 100)
      rows = @db.execute("SELECT * FROM models WHERE type = ? ORDER BY RANDOM() LIMIT ?", [type, limit])

      rows.map { |r| Model.new(**r.transform_keys(&:to_sym).slice(*Model.members)) }

    end

    def search(query, limit = 20)
      pattern = "%#{query}%"

      rows = @db.execute(

        "SELECT * FROM models WHERE id LIKE ? OR description LIKE ? ORDER BY runs DESC LIMIT ?",

        [pattern, pattern, limit]

      )

      rows.map { |r| Model.new(**r.transform_keys(&:to_sym).slice(*Model.members)) }

    end

    def random(count = 10)
      rows = @db.execute("SELECT * FROM models ORDER BY RANDOM() LIMIT ?", [count])

      rows.map { |r| Model.new(**r.transform_keys(&:to_sym).slice(*Model.members)) }

    end

    def count
      @db.execute("SELECT COUNT(*) as c FROM models")[0]["c"]

    end

    def stats
      total = count

      by_type = @db.execute("SELECT type, COUNT(*) as count FROM models WHERE type IS NOT NULL GROUP BY type ORDER BY count DESC")

      { total: total, by_type: by_type }

    end

  end

end

