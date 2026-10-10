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

  def test_model_none_clears_an_inherited_model
    with_worktree do |main, worker, tools_bin|
      write_main_model(main)

      output, status = run_fix_here(
        worker, tools_bin, "MASTER", "--model", "none", "--no-probe",
        env: { "MASTER_MODEL" => "inherited-model" },
      )

      assert status.success?, output
      log = File.read(File.join(worker, "MASTER/.master/fix-MASTER.log"))
      assert_includes log, "child-model=UNSET"
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

  private

  def with_worktree
    Dir.mktmpdir("fix-here-test") do |directory|
      main = File.join(directory, "main")
      worker = File.join(directory, "worker")
      tools_bin = File.join(directory, "bin")
      FileUtils.mkdir_p(File.join(main, "MASTER/bin"))
      FileUtils.mkdir_p(tools_bin)
      FileUtils.cp(SCRIPT, File.join(main, "MASTER/bin/fix-here"))
      File.write(
        File.join(main, "MASTER/bin/master"),
        "#!/usr/bin/env ruby\nputs 'child-model=' + ENV.fetch('MASTER_MODEL', 'UNSET') + \"\\n\"\n",
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
