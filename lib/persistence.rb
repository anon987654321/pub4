require 'sqlite3'

module MASTER
  class Persistence
    def initialize(db_path)
      @db = SQLite3::Database.new db_path
      @db.execute("CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY, data TEXT)")
    end

    def save_session(data)
      @db.transaction do
        @db.execute("INSERT INTO sessions (data) VALUES (?)", [data.to_json])
      end
    end

    def load_session(id)
      @db.get_first_value("SELECT data FROM sessions WHERE id = ?", id)
    end
  end
end
