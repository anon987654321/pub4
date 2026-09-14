# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "sqlite3"

require_relative "../lib/ground/sqlite_store"

class TestSqliteStorePersistence < Minitest::Test
  include Master::Ground::SqliteStore

  def test_ephemeral_database_is_not_silent
    original = ENV["MASTER_ALLOW_EPHEMERAL_DB"]
    ENV.delete("MASTER_ALLOW_EPHEMERAL_DB")
    error = assert_raises(SQLite3::Exception) do
      ephemeral_database("/definitely/unavailable/master.sqlite3")
    end
    assert_match(/persistent database unavailable/, error.message)
  ensure
    ENV["MASTER_ALLOW_EPHEMERAL_DB"] = original
  end
end
