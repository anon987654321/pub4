# frozen_string_literal: true

require_relative "test_helper"

class TestSqliteStore < Minitest::Test
  Store = Class.new do
    include Master::Ground::SqliteStore
  end

  def test_opens_database_when_chmod_is_not_supported
    Dir.mktmpdir("sqlite_store") do |root|
      database = nil
      chmod = ->(*) { raise Errno::ENOSYS }

      FileUtils.stub(:chmod, chmod) do
        _stdout, stderr = capture_io do
          database = Store.new.open_sqlite(root, ".master/test.sqlite3")
          database.execute("CREATE TABLE example (value TEXT)")
        end

        assert_includes stderr, "chmod unsupported"
      end

      assert File.exist?(File.join(root, ".master", "test.sqlite3"))
    ensure
      database&.close
    end
  end

  def test_does_not_ignore_chmod_permission_errors
    Dir.mktmpdir("sqlite_store") do |root|
      chmod = ->(*) { raise Errno::EACCES }

      FileUtils.stub(:chmod, chmod) do
        assert_raises(Errno::EACCES) do
          Store.new.open_sqlite(root, ".master/test.sqlite3")
        end
      end
    end
  end
end
