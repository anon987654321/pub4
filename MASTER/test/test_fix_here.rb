# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "open3"
require "rbconfig"

class TestFixHere < Minitest::Test
  SCRIPT = File.expand_path("../bin/fix-here", __dir__)

  def test_dry_run_does_not_create_the_worktree_model_directory
    with_worktree do |main, worker, tools_bin|
      write_main_model(main)

      output, status = run_fix_here(worker, tools_bin, "MASTER", "--dry")

      assert status.success?, output
      refute File.exist?(File.join(worker, "MASTER/.master")),
             "--dry must not create a directory while declining to copy the config"
    end
  end

  def test_failed_disk_probe_is_reported_as_unreadable
    with_worktree do |_main, worker, tools_bin|
      df = File.join(tools_bin, "df")
      File.write(df, "#!/bin/sh\nexit 1\n")
      FileUtils.chmod(0o755, df)

      output, status = run_fix_here(worker, tools_bin, "MASTER", "--dry")

      refute status.success?
      assert_includes output, "cannot read free disk"
      refute_includes output, "need 2.0"
    end
  end

  def test_malformed_disk_probe_output_is_reported_as_unreadable
    with_worktree do |_main, worker, tools_bin|
      df = File.join(tools_bin, "df")
      File.write(df, "#!/bin/sh\nprintf 'not a df table\\n'\n")
      FileUtils.chmod(0o755, df)

      output, status = run_fix_here(worker, tools_bin, "MASTER", "--dry")

      refute status.success?
      assert_includes output, "cannot read free disk"
      refute_includes output, "need 2.0"
    end
  end

  def test_model_none_clears_an_inherited_model
    with_worktree do |main, worker, tools_bin|
      write_main_model(main)

      output, status = run_fix_here(
        worker, tools_bin, "MASTER", "--model", "none", "--no-probe",
        env: { "MASTER_MODEL" => "inherited-model" }
      )

      assert status.success?, output
      log = File.read(File.join(worker, "MASTER/.master/fix-MASTER.log"))
      assert_includes log, "child-model=UNSET"
    end
  end

  def test_no_publish_reaches_the_run_and_is_absent_without_the_flag
    with_worktree do |_main, worker, tools_bin|
      _, held = run_fix_here(worker, tools_bin, "MASTER", "--model", "none", "--no-probe", "--no-publish")
      assert held.success?
      assert_includes File.read(File.join(worker, "MASTER/.master/fix-MASTER.log")), "no-publish=1"

      _, normal = run_fix_here(worker, tools_bin, "MASTER", "--model", "none", "--no-probe")
      assert normal.success?
      assert_includes File.read(File.join(worker, "MASTER/.master/fix-MASTER.log")), "no-publish=UNSET"
    end
  end

  def test_model_flag_requires_a_value
    with_worktree do |_main, worker, tools_bin|
      output, status = run_fix_here(worker, tools_bin, "MASTER", "--model")

      refute status.success?
      assert_includes output, "--model requires"
      refute File.exist?(File.join(worker, "MASTER/.master"))
    end
  end

  def test_a_child_that_exits_zero_after_an_option_error_fails_the_wrapper
    with_worktree do |_main, worker, tools_bin|
      output, status = run_fix_here(
        worker, tools_bin, "MASTER", "--model", "none", "--no-probe",
        env: { "FAKE_FIRST_LINE" => "cli0: option error, invalid option: --max-files=25" }
      )

      assert_equal 70, status.exitstatus, output
      assert_includes output, "rejected an option"
    end
  end

  def test_no_critique_and_the_check_list_reach_the_run
    with_worktree do |_main, worker, tools_bin|
      output, status = run_fix_here(worker, tools_bin, "MASTER", "--model", "none", "--no-probe", "--no-critique", "--checks=lexical,sprawl")

      assert_equal 0, status.exitstatus, output
      log = File.read(File.join(worker, "MASTER/.master/fix-MASTER.log"))
      assert_includes log, "args=/fix MASTER --no-critique"
      assert_includes log, "checks=lexical,sprawl"
    end
  end

  def test_a_child_that_never_starts_fix_fails_the_wrapper
    with_worktree do |_main, worker, tools_bin|
      output, status = run_fix_here(
        worker, tools_bin, "MASTER", "--model", "none", "--no-probe",
        env: { "FAKE_FIRST_LINE" => "master0: booted" }
      )

      assert_equal 70, status.exitstatus, output
      assert_includes output, "never started"
    end
  end

  def test_term_to_the_wrapper_reaches_the_run
    with_worktree do |_main, worker, tools_bin|
      pidfile = File.join(worker, "child.pid")
      env = { "PATH" => "#{tools_bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH', '')}", "FAKE_PIDFILE" => pidfile }
      wrapper = Process.spawn(env, RbConfig.ruby, File.join(worker, "MASTER/bin/fix-here"), "MASTER", "--model", "none", "--no-probe",
                              chdir: worker, out: File::NULL, err: File::NULL)
      30.times { break if File.exist?(pidfile) && !File.read(pidfile).empty?; sleep 0.2 }
      child = File.read(pidfile).to_i
      Process.kill("TERM", wrapper)
      Process.wait(wrapper)
      sleep 0.3
      gone = begin
        Process.kill(0, child) && false
      rescue Errno::ESRCH
        true
      end
      Process.kill("KILL", child) unless gone
      assert gone, "the run kept going after the wrapper was terminated"
    end
  end

  def test_a_run_that_ignores_term_is_killed_after_the_grace_period
    with_worktree do |_main, worker, tools_bin|
      pidfile = File.join(worker, "child.pid")
      env = { "PATH" => "#{tools_bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH', '')}", "FAKE_PIDFILE" => pidfile,
              "FAKE_IGNORE_TERM" => "1", "FIX_HERE_KILL_AFTER_S" => "2" }
      wrapper = Process.spawn(env, RbConfig.ruby, File.join(worker, "MASTER/bin/fix-here"), "MASTER", "--model", "none", "--no-probe",
                              chdir: worker, out: File::NULL, err: File::NULL)
      30.times { break if File.exist?(pidfile) && !File.read(pidfile).empty?; sleep 0.2 }
      child = File.read(pidfile).to_i
      Process.kill("TERM", wrapper)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Process.wait(wrapper)
      sleep 0.3
      gone = begin
        Process.kill(0, child) && false
      rescue Errno::ESRCH
        true
      end
      Process.kill("KILL", child) unless gone
      assert gone, "a run that ignores TERM outlived the wrapper"
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 15
    end
  end

  def test_a_failed_lane_check_shows_what_the_call_printed
    with_worktree do |main, worker, tools_bin|
      write_main_model(main)
      output, status = run_fix_here(
        worker, tools_bin, "MASTER",
        env: { "FAKE_FIRST_LINE" => "rbenv: version 4.0.7 is not installed", "FAKE_EXIT" => "3" }
      )

      refute status.success?, output
      assert_includes output, "the lane check wrote no metrics"
      assert_includes output, "rbenv: version 4.0.7 is not installed"
    end
  end

  def test_the_launchers_run_when_the_ruby_on_path_refuses_the_pinned_version
    Dir.mktmpdir("shim") do |dir|
      File.write(File.join(dir, "ruby"), "#!/bin/sh\necho \"rbenv: version 9.9.9 is not installed\" >&2\nexit 1\n")
      FileUtils.chmod(0o755, File.join(dir, "ruby"))
      env = { "PATH" => "#{dir}:/usr/bin:/bin" }
      %w[fix-here].each do |name|
        out, status = Open3.capture2e(env, File.expand_path("../bin/#{name}", __dir__), "--help")

        refute_includes out, "is not installed", "#{name}: #{out}"
        assert status.exitstatus.is_a?(Integer), name
      end
    end
  end

  private

  def with_worktree
    Dir.mktmpdir("fix-here-test") do |directory|
      main = File.join(directory, "main")
      worker = File.join(directory, "worker")
      tools_bin = File.join(directory, "bin")
      FileUtils.mkdir_p(File.join(main, "MASTER/bin"))
      FileUtils.mkdir_p(tools_bin)
      FileUtils.cp(SCRIPT, File.join(main, "MASTER/bin/fix-here"))
      FileUtils.cp(File.expand_path("../bin/ruby", __dir__), File.join(main, "MASTER/bin/ruby"))
      FileUtils.chmod(0o755, File.join(main, "MASTER/bin/ruby"))
      FileUtils.mkdir_p(File.join(main, "MASTER/lib/operator"))
      %w[parse_sweep stall_watch].each { |n| FileUtils.cp(File.expand_path("../lib/operator/#{n}.rb", __dir__), File.join(main, "MASTER/lib/operator")) }
      File.write(
        File.join(main, "MASTER/bin/master"),
        "#!/usr/bin/env ruby\ntrap('TERM', 'IGNORE') if ENV['FAKE_IGNORE_TERM']\nputs ENV.fetch('FAKE_FIRST_LINE', 'fix0 fake run')\n$stdout.flush\nexit ENV['FAKE_EXIT'].to_i if ENV['FAKE_EXIT']\nif ENV['FAKE_PIDFILE'] then File.write(ENV['FAKE_PIDFILE'], Process.pid.to_s); sleep 60 end\nputs 'child-model=' + ENV.fetch('MASTER_MODEL', 'UNSET') + \"\n\"\nputs 'no-publish=' + ENV.fetch('MASTER_FIX_NO_PUBLISH', 'UNSET') + \"\n\"\nputs 'args=' + ARGV.join(' ') + \"\n\"\nputs 'checks=' + ENV.fetch('MASTER_FIX_CHECK_STAGES', 'UNSET') + \"\n\"\n",
      )
      FileUtils.chmod(0o755, File.join(main, "MASTER/bin/fix-here"))
      FileUtils.chmod(0o755, File.join(main, "MASTER/bin/master"))
      File.write(
        File.join(tools_bin, "df"),
        "#!/bin/sh\nprintf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/test 100000000 1 100000000 1%% /\\n'\n",
      )
      FileUtils.chmod(0o755, File.join(tools_bin, "df"))

      git(main, "init", "-q", "--initial-branch=main")
      git(main, "config", "user.name", "MASTER test")
      git(main, "config", "user.email", "master-test@example.invalid")
      git(main, "add", "-A")
      git(main, "commit", "-qm", "test fixture")
      git(main, "worktree", "add", "-q", "-b", "worker", worker, "HEAD")

      yield main, worker, tools_bin
    end
  end

  def write_main_model(main)
    path = File.join(main, "MASTER/.master/config.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "model: saved-model\n")
  end

  def run_fix_here(worker, tools_bin, *args, env: {})
    child_env = {
      "PATH" => "#{tools_bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH', '')}",
    }.merge(env)
    Open3.capture2e(child_env, RbConfig.ruby, File.join(worker, "MASTER/bin/fix-here"), *args, chdir: worker)
  end

  def git(root, *args)
    _output, status = Open3.capture2e("git", "-C", root, *args)
    raise "git fixture command failed: #{args.join(' ')}" unless status.success?
  end
end
