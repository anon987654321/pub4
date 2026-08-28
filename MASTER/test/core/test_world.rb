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

  # within() stops a path leaving root and said nothing about what sits inside
  # it, so a credential file in the checkout was readable and its contents
  # landed in the transcript.
  def test_read_refuses_credential_files_inside_the_workspace
    %w[.env .env.production credentials.yml secrets.json id_rsa api_keys.txt].each do |name|
      with_world do |world, root|
        File.write(File.join(root, name), "SECRET=hunter2\n")
        obs = world.perform(E.read(name))
        refute obs.ok?, "#{name} was readable"
        refute_includes obs.message.to_s, "hunter2"
      end
    end
  end

  def test_write_refuses_credential_files
    with_world do |world, root|
      obs = world.perform(E.write(".env", "SECRET=hunter2\n"))
      refute obs.ok?
      refute File.exist?(File.join(root, ".env"))
    end
  end

  # The rule is the file's own name, not the word anywhere in the path: a
  # directory called secrets_handling/ or a file named environment.rb is
  # ordinary source and refusing it would make the agent useless in this tree.
  def test_ordinary_files_that_merely_resemble_secrets_still_read
    %w[environment.rb keyboard.js private_notes_test.rb tokenizer.rb].each do |name|
      with_world do |world, root|
        File.write(File.join(root, name), "ok\n")
        assert world.perform(E.read(name)).ok?, "#{name} was refused"
      end
    end
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

  # exec output becomes an Observation, Memory records it, and the next turn hands
  # it back to the model — so anything the child can read, the model can read.
  # `env: nil` inherited the whole process environment, which on this box holds
  # OPENROUTER_API_KEY and friends, so `exec(["env"])` was a supported way to
  # print every credential into the transcript.
  def test_exec_does_not_pass_credentials_to_the_child
    with_world do |world, _root|
      ENV["MASTER_TEST_FAKE_API_KEY"] = "sk-should-never-be-visible"
      ENV["MASTER_TEST_AWS_SECRET_ACCESS_KEY"] = "aws-should-never-be-visible"
      ENV["MASTER_TEST_ORDINARY_VAR"] = "ordinary-and-inherited"

      obs = world.perform(E.exec(%w[env]))
      assert obs.ok?, obs.message

      refute_includes obs.value!, "sk-should-never-be-visible", "an API key reached the child"
      refute_includes obs.value!, "aws-should-never-be-visible", "an AWS secret reached the child"
      # The toolchain still has to work — the fold earns its evidence by running
      # bundle/rake, so this must not become a blanket scrub of the environment.
      assert_includes obs.value!, "ordinary-and-inherited", "ordinary environment was stripped too"
    ensure
      %w[MASTER_TEST_FAKE_API_KEY MASTER_TEST_AWS_SECRET_ACCESS_KEY MASTER_TEST_ORDINARY_VAR].each { |k| ENV.delete(k) }
    end
  end

  # A real repository, because the whole claim here is about what git does with
  # the index and nothing short of git can answer that.
  def with_git_world
    Dir.mktmpdir do |root|
      %w[init -q].then { |a| system("git", *a, root, out: File::NULL, err: File::NULL) }
      %w[user.email a@b.c user.name tester].each_slice(2) do |k, v|
        system("git", "-C", root, "config", k, v, out: File::NULL, err: File::NULL)
      end
      File.write(File.join(root, "seed.txt"), "seed\n")
      system("git", "-C", root, "add", "seed.txt", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "commit", "-qm", "seed", out: File::NULL, err: File::NULL)
      yield Master::Core::World.new(root:), root
    end
  end

  def committed_paths(root)
    `git -C #{root} show --name-only --format= HEAD`.split("\n").map(&:strip).reject(&:empty?)
  end

  # The one that matters. This checkout is shared — other sessions and a human
  # stage things in the same index — so a bare `git commit` takes their work and
  # signs the fold's message on it. CLAUDE.md forbids exactly this of agents, and
  # the fold was the agent doing it.
  def test_commit_does_not_carry_someone_elses_staged_file
    with_git_world do |world, root|
      File.write(File.join(root, "mine.rb"), "MINE = 1\n")
      File.write(File.join(root, "theirs.rb"), "THEIRS = 1\n")
      # Somebody else's work, already staged, sitting in the shared index.
      system("git", "-C", root, "add", "theirs.rb", out: File::NULL, err: File::NULL)
      # The fold stages its own file the way it actually does — a new path has to
      # be tracked before a scoped commit can name it. Both files are now staged,
      # which is precisely the situation the bare commit used to sweep up.
      world.perform(E.git(:stage, paths: ["mine.rb"]))

      obs = world.perform(E.git(:commit, paths: ["mine.rb"], message: "mine only"))
      assert obs.ok?, obs.message

      assert_equal ["mine.rb"], committed_paths(root)
      refute_includes committed_paths(root), "theirs.rb", "the fold committed another session's staged file"
    end
  end

  # Refused rather than defaulted: guessing "everything I touched" is a decision
  # made by the layer with the least information, and it is unrecoverable when wrong.
  def test_commit_without_paths_is_refused
    with_git_world do |world, root|
      File.write(File.join(root, "theirs.rb"), "THEIRS = 1\n")
      system("git", "-C", root, "add", "theirs.rb", out: File::NULL, err: File::NULL)

      obs = world.perform(E.git(:commit, message: "everything"))
      refute obs.ok?, "an unscoped commit must not run"
      assert_match(/paths/, obs.message)
      assert_equal ["seed.txt"], committed_paths(root), "HEAD moved despite the refusal"
    end
  end
end
