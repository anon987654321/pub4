# frozen_string_literal: true

require "minitest/autorun"
require "master"
require "tmpdir"

# The World is the only door to reality, so its handlers carry the whole blast
# radius of the agent. These pin the invariants every handler must hold:
# the sandbox never opens, writes replace atomically, and a failed exec is
# reported as data (err Observation), never raised.
class WorldTest < Minitest::Test
  E = Master::Core::Effect

  def with_world
    Dir.mktmpdir { |root| yield Master::Core::World.new(root:), root }
  end

  def test_read_returns_file_contents
    with_world do |world, root|
      File.write(File.join(root, "a.txt"), "hello\n")
      obs = world.perform(E.read("a.txt"))
      assert obs.ok?
      assert_equal "hello\n", obs.value!
    end
  end

  def test_write_creates_nested_dirs_and_content
    with_world do |world, root|
      obs = world.perform(E.write("deep/nested/a.rb", "A = 1\n"))
      assert obs.ok?, obs.message
      assert_equal "A = 1\n", File.read(File.join(root, "deep/nested/a.rb"))
    end
  end

  def test_write_replaces_existing_atomically_and_leaves_no_tmp
    with_world do |world, root|
      File.write(File.join(root, "a.rb"), "old\n")
      world.perform(E.write("a.rb", "new\n"))
      assert_equal "new\n", File.read(File.join(root, "a.rb"))
      # No .tmp or .bak litter beside the target — the write is one atomic rename.
      assert_equal ["a.rb"], Dir.children(root).sort
    end
  end

  def test_path_escaping_the_sandbox_is_refused_not_raised
    with_world do |world|
      obs = world.perform(E.read("../../etc/passwd"))
      assert obs.err?
      assert_match(/escapes workspace/, obs.message)
    end
  end

  def test_write_escaping_the_sandbox_is_refused
    with_world do |world, root|
      obs = world.perform(E.write("../evil.txt", "x"))
      assert obs.err?
      refute File.exist?(File.expand_path("../evil.txt", root))
    end
  end

  def test_a_symlink_out_of_the_workspace_cannot_be_read
    with_world do |world, root|
      outside = File.join(File.dirname(root), "outside-#{SecureRandom.hex(4)}.txt")
      File.write(outside, "secret\n")
      File.symlink(outside, File.join(root, "leak"))
      obs = world.perform(E.read("leak"))
      assert obs.err?, "symlink out of the sandbox must not be readable"
      refute_match(/secret/, obs.message.to_s)
    ensure
      File.delete(outside) if outside && File.exist?(outside)
    end
  end

  def test_exec_does_not_honor_model_chosen_env
    with_world do |world|
      obs = world.perform(E.exec(
        [RbConfig.ruby, "-e", "print ENV['WORLD_PROBE'].to_s"],
        env: { "WORLD_PROBE" => "injected" },
      ))
      assert obs.ok?
      assert_equal "", obs.value!
    end
  end

  def test_exec_success_returns_stdout
    with_world do |world|
      obs = world.perform(E.exec([RbConfig.ruby, "-e", "print 'ok'"]))
      assert obs.ok?
      assert_equal "ok", obs.value!
    end
  end

  def test_exec_failure_is_err_observation_not_raise
    with_world do |world|
      obs = world.perform(E.exec([RbConfig.ruby, "-e", "exit 3"]))
      assert obs.err?
    end
  end

  def test_do_exec_kills_a_wedged_child
    with_world do |world|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      obs = world.perform(E.exec([RbConfig.ruby, "-e", "sleep 30"], timeout: 1))
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert obs.err?
      assert_match(/TIMEOUT/, obs.message)
      assert_operator elapsed, :<, 10, "do_exec still used Timeout.timeout around Open3"
    end
  end

  def test_exec_rejects_non_array_argv
    with_world do |world|
      obs = world.perform(E.new(verb: :exec, args: { argv: "rake test" }))
      assert obs.err?
      assert_match(/argv must be an array/, obs.message)
    end
  end

  # A timed-out subprocess has no Process::Status. bounded_capture2e used to
  # return nil in its place, so the moment git actually wedged, every caller
  # (git_repo?, git_has_head?, git_capture, apply_patch) raised NoMethodError
  # on nil — from inside the fold, the one part that has to stay standing when
  # the outside world misbehaves.
  # Real subprocess, real timeout — the nil status only appeared on the live
  # rescue path, so a stubbed clock would not have caught it.
  def test_timeout_yields_a_failed_status_not_nil
    with_bounded_timeout(1) do |world|
      out, status = world.send(:bounded_capture2e, RbConfig.ruby, "-e", "sleep 30")

      refute_nil status, "a timeout must still answer #success?"
      refute status.success?
      assert_match(/TIMEOUT after 1s/, out)
    end
  end

  # The bound has to kill the child, not just stop waiting for it. Wrapping
  # Open3.capture3 in Timeout.timeout only unwound the block: the process kept
  # running and Ruby blocked on it at exit, so a 1s timeout around `sleep 30`
  # took 30 seconds. Anything near the deadline proves the kill happened.
  def test_timeout_kills_the_child_instead_of_waiting_for_it
    with_bounded_timeout(1) do |world|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      world.send(:bounded_capture2e, RbConfig.ruby, "-e", "sleep 30")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator elapsed, :<, 10, "returned after #{elapsed.round(1)}s — the child outlived the bound"
    end
  end

  def test_bounded_capture_still_returns_output_and_status_normally
    with_world do |world|
      out, status = world.send(:bounded_capture2e, RbConfig.ruby, "-e", "$stdout.print 'o'; $stderr.print 'e'")

      assert_equal "oe", out, "stdout and stderr are merged, in that order"
      assert status.success?
    end
  end

  # A child that outruns its pipe buffer must not deadlock the reader.
  def test_bounded_capture_survives_output_larger_than_the_pipe_buffer
    with_world do |world|
      out, status = world.send(:bounded_capture2e, RbConfig.ruby, "-e", "$stdout.print('x' * 200_000)")

      assert status.success?
      assert_equal 200_000, out.bytesize
    end
  end

  def with_bounded_timeout(seconds)
    previous = ENV["MASTER_EXEC_TIMEOUT"]
    ENV["MASTER_EXEC_TIMEOUT"] = seconds.to_s
    with_world { |world| yield world }
  ensure
    previous ? ENV["MASTER_EXEC_TIMEOUT"] = previous : ENV.delete("MASTER_EXEC_TIMEOUT")
  end

  def test_git_capture_raises_the_timeout_message_when_git_wedges
    with_world do |world|
      wedge_git(world)
      error = assert_raises(RuntimeError) { world.send(:git_capture, "status") }
      assert_match(/TIMEOUT/, error.message)
    end
  end

  def test_checkpoint_survives_a_wedged_git
    with_world do |world|
      wedge_git(world)
      checkpoint = world.checkpoint

      assert_equal "", checkpoint[:patch], "an unreachable git means nothing to capture, not a crash"
      refute_nil checkpoint[:id]
    end
  end

  def wedge_git(world)
    world.define_singleton_method(:bounded_capture2e) do |*, **|
      ["TIMEOUT after 1s: git", Master::Core::World::TIMED_OUT]
    end
  end
end
