# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../../../lib/pub4/ci_guard"

class CiGuardTest < Minitest::Test
  def test_enabled_when_env_guard_set
    with_env("PUB4_CI_GUARD" => "1") do
      assert Pub4::CiGuard.enabled?
    end
  end

  def test_disabled_when_env_guard_zero
    with_env("PUB4_CI_GUARD" => "0") do
      refute Pub4::CiGuard.enabled?
    end
  end

  # The lock lives in root-owned /var/db/pub4, with the shell side.
  #
  # It used to be /var/tmp/pub4-ci.lock while OPENBSD/lib/ci_lock.sh called
  # itself "the one definition of the pub4 CI mutex path" and pointed three
  # shell scripts at /var/db/pub4/ci.lock. Two lock files that excluded nothing
  # in each other, and the one that was actually being locked -- this one -- was
  # the one left in the world-writable directory that rewrite existed to escape.
  def test_lock_path_defaults_to_the_shared_root_owned_file
    with_env("PUB4_CI_LOCK" => nil) do
      assert_equal "/var/db/pub4/ci.lock", Pub4::CiGuard.lock_path
      assert_equal "/var/db/pub4/ci.lock.holder", Pub4::CiGuard.holder_path
    end
  end

  # An override is honoured on its directory's permissions, not its name. That
  # is the property the /var/tmp objection was actually about: a predictable
  # name in a directory anyone can write to is a symlink an attacker plants and
  # a privileged process then follows.
  def test_override_is_honoured_in_a_private_directory
    Dir.mktmpdir do |dir|
      File.chmod(0o755, dir)
      path = File.join(dir, "ci.lock")

      with_env("PUB4_CI_LOCK" => path) do
        assert_equal path, Pub4::CiGuard.lock_path
      end
    end
  end

  def test_override_is_refused_from_a_world_writable_directory
    Dir.mktmpdir do |dir|
      File.chmod(0o777, dir)
      path = File.join(dir, "ci.lock")

      with_env("PUB4_CI_LOCK" => path) do
        capture_stderr { assert_equal "/var/db/pub4/ci.lock", Pub4::CiGuard.lock_path }
      end
    end
  end

  def test_override_pointing_nowhere_falls_back_to_the_default
    with_env("PUB4_CI_LOCK" => "/no/such/directory/ci.lock") do
      assert_equal "/var/db/pub4/ci.lock", Pub4::CiGuard.lock_path
    end
  end

  # The lock is opened read-only, and that is what lets the file stay 0644.
  #
  # It was 0666 for a reason, and the reason is worth remembering: three deploy
  # users (brgen, amber, bsdports) open it, O_RDWR needs write permission for
  # all three, and every attempt to arrange that failed differently. The
  # requested 0o666 on File.open is masked by umask down to 0644, which broke
  # amber's deploy on 2026-07-20 with EACCES right after brgen's CI created the
  # file. chmod is not subject to umask so it was applied explicitly -- and only
  # an owner may chmod, so bsdports crashed on EPERM in the same incident. The
  # end state was a world-writable file in a world-writable directory.
  #
  # flock(2) does not need write permission. Opening read-only deletes the whole
  # chain, so this asserts the mode is not widened rather than that it is.
  def test_lock_file_is_not_made_world_writable
    in_private_lock do |path|
      Pub4::CiGuard.with_lock { nil }

      mode = File.stat(path).mode & 0o777

      assert_equal 0, mode & 0o002, "the lock must not be world-writable"
    end
  end

  def test_with_lock_yields_and_returns_the_block_value
    in_private_lock do
      assert_equal :yielded, Pub4::CiGuard.with_lock { :yielded }
    end
  end

  def test_holder_file_exists_while_the_lock_is_held_and_not_after
    in_private_lock do |path|
      holder = "#{path}.holder"
      during = nil

      Pub4::CiGuard.with_lock { during = File.exist?(holder) }

      assert during, "holder file should exist while the lock is held"
      refute_path_exists holder, "holder file should be removed on release"
    end
  end

  # A holder note is a diagnostic. A mutex that refuses to be taken because it
  # could not write a comment about itself would be worse than one nobody can
  # attribute.
  def test_an_unwritable_holder_does_not_break_the_lock
    in_private_lock do
      original = File.method(:write)
      File.define_singleton_method(:write) { |*| raise Errno::EACCES, "Permission denied" }

      begin
        assert_equal :yielded, Pub4::CiGuard.with_lock { :yielded }
      ensure
        File.define_singleton_method(:write, original)
      end
    end
  end

  # A lock file that cannot be opened at all is a real failure a non-owner
  # process cannot self-heal. Report it (warn + exit 1) rather than crashing
  # with an uncaught backtrace.
  def test_with_lock_reports_eacces_on_open_instead_of_crashing
    in_private_lock do |path|
      original = File.method(:open)
      File.define_singleton_method(:open) do |*args, &blk|
        raise Errno::EACCES, "Permission denied" if args.first == path

        original.call(*args, &blk)
      end

      begin
        error = nil
        capture_stderr { error = assert_raises(SystemExit) { Pub4::CiGuard.with_lock { :yielded } } }

        assert_equal 1, error.status
      ensure
        File.define_singleton_method(:open, original)
      end
    end
  end

  # Reporting who holds a busy lock must not itself raise: a holder file written
  # by a different user under a stricter umask would otherwise crash the
  # busy-lock path, which is exactly when the message matters.
  def test_safe_read_falls_back_to_unknown_on_eacces
    original = File.method(:read)
    File.define_singleton_method(:read) { |*| raise Errno::EACCES, "Permission denied" }
    begin
      assert_equal "unknown", Pub4::CiGuard.safe_read(__FILE__)
    ensure
      File.define_singleton_method(:read, original)
    end
  end

  # An unreadable load average must not read as an idle box. CiGuard fails open
  # -- a gate in front of CI that treats unknown as busy is indistinguishable
  # from a permanently locked one -- but it says so instead of returning 0.0 in
  # silence, which in a log looks like a machine with nothing to do.
  def test_unreadable_load_warns_rather_than_reporting_zero
    err = nil
    with_unreadable_load do
      err = capture_stderr { assert_in_delta 0.0, Pub4::CiGuard.current_load }
    end

    assert_includes err, "cannot read load average"
  end

  private

  # Runs the block with the guard pointed at a private lock file, so the tests
  # never touch /var/db/pub4 and never depend on being root.
  def in_private_lock
    Dir.mktmpdir do |dir|
      File.chmod(0o755, dir)
      path = File.join(dir, "ci.lock")

      with_env("PUB4_CI_LOCK" => path) { yield(path) }
    end
  end

  # minitest/mock is not available to these bare-ruby tests, so the seam is made
  # by hand and put back by hand.
  def with_unreadable_load
    sc = Pub4::LoadAverage.singleton_class
    sc.send(:alias_method, :five_before_stub, :five)
    sc.send(:define_method, :five) { nil }
    yield
  ensure
    sc.send(:remove_method, :five)
    sc.send(:alias_method, :five, :five_before_stub)
    sc.send(:remove_method, :five_before_stub)
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  def with_env(vars)
    previous = vars.to_h { |k, _| [k, ENV.fetch(k, nil)] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
