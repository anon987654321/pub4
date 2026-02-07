require 'sqlite3'

module MASTER
  class Persistence
    def initialize(db_path)
      @db = SQLite3::Database.new(db_path)
      @db.execute("CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY, data TEXT)")
    end

    def save_session(data)
      @db.execute("INSERT INTO sessions (data) VALUES (?)", [data.to_json])
    end

    def load_session(id)
      row = @db.execute("SELECT data FROM sessions WHERE id = ?", id).first
      JSON.parse(row[0]) if row
    end
  end
end
