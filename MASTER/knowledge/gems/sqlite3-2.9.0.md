# frozen_string_literal: true
require "sqlite3"
require "tempfile"

# SQLite3 gem usage demo
# ----------------------
# * Creates an isolated temporary SQLite file.
# * Shows safe table creation, parameterised inserts, and data retrieval.
# * Demonstrates atomic transactions via `db.transaction { … }`.
# * All resources are closed automatically via block syntax.

Tempfile.create(["demo", ".db"]) do |tmp|
  SQLite3::Database.open(tmp.path) do |db|
    # ------------------------------------------------------------------
    # 1️⃣ Simple numeric table
    # ------------------------------------------------------------------
    db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS numbers (
        name TEXT,
        val  INTEGER
      );
    SQL

    # Atomic insertion – rolls back on error
    db.transaction do
      { "one" => 1, "two" => 2 }.each do |name, value|
        db.execute("INSERT INTO numbers (name, val) VALUES (?, ?)", [name, value])
      end
    end

    puts "Numbers table contents:"
    db.execute("SELECT * FROM numbers") { |row| p row }

    # ------------------------------------------------------------------
    # 2️⃣ More complex table
    # ------------------------------------------------------------------
    db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS students (
        name   TEXT,
        email  TEXT,
        grade  TEXT,
        blog   TEXT
      );
    SQL

    # Single, safe insertion wrapped in a transaction
    db.transaction do
      db.execute(
        "INSERT INTO students (name, email, grade, blog) VALUES (?, ?, ?, ?)",
        ["Jane", "me@janedoe.com", "A", "http://blog.janedoe.com"]
      )
    end

    puts "\nStudents table contents:"
    db.execute("SELECT * FROM students") { |row| p row }
  end
end
# The outer block auto‑closes the temporary file and the SQLite connection,
# guaranteeing no lingering resources.