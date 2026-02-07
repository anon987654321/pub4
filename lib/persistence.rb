require 'sqlite3'
require 'json'

module MASTER
  class Persistence
    def initialize(db_path)
      @db_path = db_path
      @db = SQLite3::Database.new db_path
      @db.execute("CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY, data TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)")
      @db.execute("CREATE TABLE IF NOT EXISTS stats (key TEXT PRIMARY KEY, value TEXT)")
    end

    def save_session(data)
      @db.transaction do
        id = @db.execute("INSERT INTO sessions (data) VALUES (?) RETURNING id", [data.to_json])[0][0]
        data['id'] = id
      end
      data
    end

    def load_session(id)
      row = @db.execute("SELECT data FROM sessions WHERE id = ?", id).first
      JSON.parse(row[0]) if row
    end

    def get_recent_sessions(limit = 10)
      @db.execute("SELECT data FROM sessions ORDER BY timestamp DESC LIMIT ?", limit).map { |row| JSON.parse(row[0]) }
    end

    def update_stats(key, value)
      @db.execute("INSERT OR REPLACE INTO stats (key, value) VALUES (?, ?)", [key, value.to_s])
    end

    def get_stats(key)
      row = @db.execute("SELECT value FROM stats WHERE key = ?", key).first
      row ? JSON.parse(row[0]) : nil
    end
  end
end
