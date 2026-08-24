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

  # check_load! used to exit(1) the moment load was over the limit. It runs from
  # inside bin/ci, which vps_ci starts *after* syncing the tracked tree into
  # /home/<app>/app — so an exit there abandoned a half-applied deploy rather
  # than declining to start one. The spike it fires on is the deploy's own wake:
  # brgen measured 3.32/4.04/3.43 during a four-app pass and 0.32 alone.
  def test_load_under_the_limit_returns_without_waiting
    with_load(1.0) do
      slept = record_sleeps { Pub4::CiGuard.check_load! }

      assert_empty slept, "a quiet box must not wait at all"
    end
  end

  def test_load_over_the_limit_waits_and_proceeds_when_it_falls
    readings = [ 9.0, 9.0, 0.5 ]
    with_load_sequence(readings) do
      slept = nil
      err = capture_stderr { slept = record_sleeps { Pub4::CiGuard.check_load! } }

      assert_equal [ 20, 20 ], slept, "must poll twice, then proceed on the third reading"
      assert_includes err, "waiting"
    end
  end

  def test_load_that_never_falls_gives_up_rather_than_waiting_forever
    with_env("PUB4_CI_LOAD_WAIT" => "0") do
      with_load(9.0) do
        code = nil
        # SystemExit unwinds through capture_stderr, so the raise has to be caught
        # inside it or the captured string never gets returned.
        err = capture_stderr { code = assert_raises(SystemExit) { Pub4::CiGuard.check_load! } }

        assert_equal 1, code.status
        assert_includes err, "giving up"
      end
    end
  end

  private

  def with_load(value, &block) = with_load_sequence([ value ], &block)

  # minitest/mock is unavailable to these bare-ruby tests, so the seam is a
  # singleton override. Saved and re-aliased rather than removed: module_function
  # defines current_load *as* the singleton method, so remove_method deletes the
  # real one and every later test in the file dies on NoMethodError.
  def with_load_sequence(values)
    queue = values.dup
    stub_singleton(:current_load) { queue.size > 1 ? queue.shift : queue.first }
    yield
  ensure
    unstub_singleton(:current_load)
  end

  def record_sleeps
    slept = []
    stub_singleton(:sleep) { |n| slept << n }
    yield
    slept
  ensure
    unstub_singleton(:sleep)
  end

  def stub_singleton(name, &body)
    meta = Pub4::CiGuard.singleton_class
    meta.send(:alias_method, :"__real_#{name}", name) if Pub4::CiGuard.respond_to?(name)
    Pub4::CiGuard.define_singleton_method(name, &body)
  end

  def unstub_singleton(name)
    meta = Pub4::CiGuard.singleton_class
    meta.send(:remove_method, name)
    return unless meta.method_defined?(:"__real_#{name}") || meta.private_method_defined?(:"__real_#{name}")

    meta.send(:alias_method, name, :"__real_#{name}")
    meta.send(:remove_method, :"__real_#{name}")
  end

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
    previous = vars.to_h { |k, _| [ k, ENV.fetch(k, nil) ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
