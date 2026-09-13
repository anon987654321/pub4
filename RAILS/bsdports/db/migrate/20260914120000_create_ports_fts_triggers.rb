# frozen_string_literal: true

# The SQLite adapter's execute runs the first statement of a string and drops
# the rest, so 20260528000100_create_ports_fts.rb built the virtual table and
# never its backfill or its three triggers. One statement per execute here, each
# idempotent, which also lets config/application.rb rerun this after a schema
# load.
class CreatePortsFtsTriggers < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      CREATE VIRTUAL TABLE IF NOT EXISTS ports_fts USING fts5(
        name, comment, content='ports', content_rowid='id', tokenize='unicode61'
      )
    SQL
    execute <<~SQL.squish
      CREATE TRIGGER IF NOT EXISTS ports_ai AFTER INSERT ON ports BEGIN
        INSERT INTO ports_fts(rowid, name, comment)
          VALUES (new.id, new.name, COALESCE(new.comment, ''));
      END
    SQL
    execute <<~SQL.squish
      CREATE TRIGGER IF NOT EXISTS ports_au AFTER UPDATE ON ports BEGIN
        INSERT INTO ports_fts(ports_fts, rowid, name, comment)
          VALUES ('delete', old.id, old.name, COALESCE(old.comment, ''));
        INSERT INTO ports_fts(rowid, name, comment)
          VALUES (new.id, new.name, COALESCE(new.comment, ''));
      END
    SQL
    execute <<~SQL.squish
      CREATE TRIGGER IF NOT EXISTS ports_ad AFTER DELETE ON ports BEGIN
        INSERT INTO ports_fts(ports_fts, rowid, name, comment)
          VALUES ('delete', old.id, old.name, COALESCE(old.comment, ''));
      END
    SQL
    execute "INSERT INTO ports_fts(ports_fts) VALUES('rebuild')"
  end

  def down
    execute "DROP TRIGGER IF EXISTS ports_ad"
    execute "DROP TRIGGER IF EXISTS ports_au"
    execute "DROP TRIGGER IF EXISTS ports_ai"
  end
end
