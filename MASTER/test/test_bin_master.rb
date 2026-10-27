# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

# bin/master is the one MASTER entrypoint: the runtime, the fold spine, the
# exec worker, replay and help are its subcommands and flags, each pinned here.
class TestBinMaster < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  MASTER = File.join(ROOT, "bin", "master")

  def run_master(*args, env: {})
    Open3.capture2e(env, RbConfig.ruby, MASTER, *args, chdir: ROOT, stdin_data: "")
  end

  # `bin/master core` is the fold and nothing else, and bin/dogfood reads its exit
  # status as the kernel smoke. It exited 0 on every run, including the ones where
  # the fold spent all forty turns being refused, so the smoke said "ok" whatever
  # happened. The scripted no-op cannot earn proof, so the constitution must
  # refuse its done; these pin both halves of that.

  def run_core(prelude = "")
    Dir.mktmpdir("master-core-test") do |workspace|
      script = "#{prelude}; load File.join(#{ROOT.inspect}, 'bin', 'master')"
      Open3.capture2e(RbConfig.ruby, "-I#{File.join(ROOT, 'lib')}", "-e", script, "--",
                      "core", "--root", workspace, "--max-turns", "6", "smoke", chdir: ROOT)
    end
  end

  def test_the_no_op_fold_is_refused_done_and_exits_zero
    out, status = run_core

    assert status.success?, out
    assert_includes out, "held, done refused without passing evidence"
  end

  def test_a_no_op_that_completes_fails_the_smoke
    out, status = run_core('require "master"; Master::Core::Proof.define_method(:proved?) { true }')

    refute status.success?, out
    assert_includes out, "core0: complete, scripted done was not refused"
  end

  # Core::World runs every model-proposed command through this worker, before the
  # boot and without RubyGems; the worker refuses a call with no command.
  def test_the_exec_worker_runs_a_command_without_booting
    out, status = Open3.capture2e(RbConfig.ruby, "--disable-gems", MASTER, "--exec-worker", "--", "echo", "worked")

    assert status.success?, out
    assert_equal "worked", out.strip

    out, status = Open3.capture2e(RbConfig.ruby, "--disable-gems", MASTER, "--exec-worker")
    assert_equal 64, status.exitstatus, out
  end

  def test_help_lists_the_subcommands_and_the_runtime_flags
    out, status = run_master("--help")

    assert status.success?, out
    ["bin/master core", "bin/master replay", "--fix-context", "--model", "--headless", "--fast"].each do |form|
      assert_includes out, form
    end
  end

  def test_replay_without_a_sequence_is_a_usage_error
    out, status = run_master("replay")

    assert_equal 64, status.exitstatus, out
    assert_includes out, "usage master replay"
  end

  # A direct run selects its Ruby through bin/ruby exactly once; bin/ruby honours
  # PUB4_RUBY, so a recorder there counts the hops.
  def test_a_direct_run_hops_through_bin_ruby_once
    hops("BUNDLE_BIN_PATH" => nil) do |log, out, status|
      assert status.success?, out
      assert_equal ["1"], File.readlines(log, chomp: true)
    end
  end

  # Under `bundle exec` the caller already chose, and there is no hop.
  def test_a_bundled_run_keeps_its_ruby
    hops("BUNDLE_BIN_PATH" => "/bundler/exe/bundle") do |log, out, status|
      assert status.success?, out
      refute_path_exists log
    end
  end

  # The suite runs inside its bundle, and RUBYOPT or BUNDLER_SETUP alone sets
  # BUNDLE_BIN_PATH again in the child; a shell's direct run carries none of them.
  def hops(extra)
    Dir.mktmpdir("master-ruby-hop") do |dir|
      log = File.join(dir, "hops")
      recorder = File.join(dir, "ruby")
      File.write(recorder, "#!/bin/sh\necho \"$MASTER_RUBY_SELECTED\" >> #{log}\nexec #{RbConfig.ruby} \"$@\"\n")
      File.chmod(0o755, recorder)

      env = ENV.keys.grep(/\ABUNDLER?_|\ARUBYOPT\z/).to_h { |key| [key, nil] }
      env.merge!("PUB4_RUBY" => recorder, "MASTER_RUBY_REEXEC_DONE" => nil, "MASTER_RUBY_SELECTED" => nil)
      yield log, *run_master("--help", env: env.merge(extra))
    end
  end
end
