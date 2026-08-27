# frozen_string_literal: true

require_relative "test_helper"

class TestSqliteStore < Minitest::Test
  Store = Class.new do
    include Master::Ground::SqliteStore
  end

  # warn_chmod_unsupported_once keeps its flag on the module, so whichever of
  # the two stubbed tests ran second saw an empty stderr and failed on order
  # alone.
  def setup
    Master::Ground::SqliteStore.instance_variable_set(:@chmod_warned, false)
  end

  # The directory has to start out readable by others, or there is nothing to
  # harden and chmod is never reached. A directory the store creates itself is
  # already 0700, which is the case the three stubs below would silently skip.
  def with_shared_state_dir(mode: 0o2775)
    Dir.mktmpdir("sqlite_store") do |root|
      dir = File.join(root, ".master")
      FileUtils.mkdir_p(dir)
      File.chmod(mode, dir)
      yield root, dir
    end
  end

  def test_opens_database_when_chmod_is_not_supported
    with_shared_state_dir do |root, _dir|
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
    with_shared_state_dir do |root, _dir|
      chmod = ->(*) { raise Errno::EACCES }

      FileUtils.stub(:chmod, chmod) do
        assert_raises(Errno::EACCES) do
          Store.new.open_sqlite(root, ".master/test.sqlite3")
        end
      end
    end
  end

  # EPERM is not EACCES. chmod belongs to the owner, so a process given a state
  # directory owned by someone else gets EPERM for doing nothing wrong -- and on
  # vm23 that raise happened inside container bootstrap, which left the web tier
  # serving "Starting up..." with no container and nothing in any log.
  def test_tolerates_chmod_refused_by_a_directory_it_does_not_own
    with_shared_state_dir do |root, _dir|
      database = nil
      chmod = ->(*) { raise Errno::EPERM }

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

  # rc.d/master gives the daemon its state directory as dev:master 2775. Clamping
  # that to 0700 on every boot the dev CLI took is what locked the daemon out of
  # it, so hardening now removes "other" and leaves owner and group as found.
  def test_clears_other_without_taking_group_access_away
    with_shared_state_dir do |root, dir|
      database = Store.new.open_sqlite(root, ".master/test.sqlite3")
      mode = File.stat(dir).mode & 0o7777

      assert_equal 0, mode & 0o007, "world access must be removed"
      assert_equal 0o070, mode & 0o070, "group must keep rwx so the daemon can write"
      assert_equal 0o2000, mode & 0o2000, "setgid must survive so new files stay group-shared"
    ensure
      database&.close
    end
  end
end
