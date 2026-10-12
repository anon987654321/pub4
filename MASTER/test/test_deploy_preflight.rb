# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/operator/canary"

# The preflight refuses a commit that does not boot before anything on the box is
# stopped. These run it against a scratch tree and a stubbed runner; nothing here
# boots MASTER or touches vm23.
class DeployPreflightTest < Minitest::Test
  Pre = Operator::DeployPreflight

  def tree(files)
    dir = Dir.mktmpdir
    files.each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), body)
    end
    dir
  end

  def test_a_syntax_error_in_master_lib_fails_the_sweep_and_names_the_file
    dir = tree("MASTER/lib/voice/renderer/text_formatting.rb" => "def broken(\n", "MASTER/lib/ok.rb" => "x = 1\n")
    result = Pre.run(root: dir, runner: ->(*) { ["", true] })
    assert_equal ["syntax"], result.map(&:name), "the first failure stops the run"
    refute result.last.ok
    assert_includes result.last.detail, "MASTER/lib/voice/renderer/text_formatting.rb"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_rails_app_files_are_swept_too
    dir = tree("RAILS/brgen/app/models/x.rb" => "class X\n")
    refute Pre.syntax(dir).ok
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_a_clean_tree_runs_all_four_checks_in_order_with_rehearse
    dir = tree("MASTER/lib/ok.rb" => "x = 1\n")
    calls = []
    result = Pre.run(root: dir, runner: ->(argv, chdir) { calls << [argv.last, chdir.delete_prefix(dir)]; ["", true] })
    assert_equal ["syntax", "law files", "boot smoke", "rehearse"], result.map(&:name)
    assert(result.all?(&:ok))
    assert_equal ["test/test_law_files_load.rb", "tools/boot_smoke.rb", "OPENBSD/bin/rehearse"], calls.map(&:first)
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_the_box_variant_skips_rehearse
    dir = tree("MASTER/lib/ok.rb" => "x = 1\n")
    result = Pre.run(root: dir, rehearse: false, runner: ->(*) { ["", true] })
    assert_equal ["syntax", "law files", "boot smoke"], result.map(&:name)
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_a_law_that_raises_at_boot_fails_the_law_check_by_name_and_is_reported_as_refusal
    dir = tree("MASTER/lib/ok.rb" => "x = 1\n")
    runner = lambda do |argv, _chdir|
      argv.last.end_with?("test_law_files_load.rb") ? ["BASELINE_COMPATIBILITY: missing bad, good\n", false] : ["", true]
    end
    result = Pre.run(root: dir, runner:)
    assert_equal "law files", result.last.name
    text = Pre.report(result)
    assert_includes text, "FAIL preflight law files"
    assert_includes text, "BASELINE_COMPATIBILITY: missing bad, good"
    assert_includes text, "law files FAILED"
    assert_includes text, "Nothing was stopped"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_main_exits_one_on_failure_and_zero_on_a_clean_tree
    bad = tree("MASTER/lib/a.rb" => "def (\n")
    good = tree("MASTER/lib/a.rb" => "x = 1\n")
    assert_equal 1, Pre.main(["--root", bad, "--no-rehearse"], out: StringIO.new)
    assert_equal 0, Pre.syntax(good).ok ? 0 : 1
  ensure
    FileUtils.rm_rf([bad, good])
  end
  SHA = "a" * 40

  def fake_git(head: SHA, origin: SHA, dirty: "")
    lambda do |_root, *argv|
      case argv.first(2)
      when %w[rev-parse HEAD] then head
      when %w[rev-parse origin/main] then origin
      when %w[status --porcelain] then dirty
      else ""
      end
    end
  end

  def remote(env: {}, runner: ->(*) { ["", true] }, **git)
    dir = tree("MASTER/lib/ok.rb" => "x = 1\n")
    Pre.remote_command(root: dir, app: "all", env:, git: fake_git(**git), runner:, out: StringIO.new)
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_remote_command_pins_the_sha_and_attests_the_preflight
    ok, command = remote
    assert ok
    assert_equal "cd /home/dev/pub4 && VPS_DEPLOY_SHA=#{SHA} VPS_DEPLOY_PREFLIGHT_SHA=#{SHA} zsh OPENBSD/bin/vps-deploy all", command
  end

  def test_remote_command_refuses_a_failed_preflight_and_sends_nothing
    ok, reason = remote(runner: ->(argv, _c) { [argv.last.end_with?("boot_smoke.rb") ? "boom" : "", !argv.last.end_with?("boot_smoke.rb")] })
    refute ok
    assert_includes reason, "preflight failed"
    assert_includes reason, "nothing was sent to the box"
  end

  def test_remote_command_refuses_a_head_that_is_not_origin_main
    ok, reason = remote(origin: "b" * 40)
    refute ok
    assert_includes reason, "is not origin/main"
  end

  def test_remote_command_refuses_a_dirty_tree_because_it_would_judge_the_edits
    ok, reason = remote(dirty: " M MASTER/lib/x.rb\n")
    refute ok
    assert_includes reason, "tracked files are modified"
  end

  def test_remote_break_glass_needs_the_acknowledgement
    ok, reason = remote(env: { "VPS_DEPLOY_SKIP_PREFLIGHT" => "1" }, runner: ->(*) { flunk "the preflight must not run" })
    refute ok
    assert_includes reason, "I_UNDERSTAND_FAST_DEPLOY=1"

    ok, command = remote(env: { "VPS_DEPLOY_SKIP_PREFLIGHT" => "1", "I_UNDERSTAND_FAST_DEPLOY" => "1" }, runner: ->(*) { flunk "skipped" })
    assert ok
    assert_includes command, "VPS_DEPLOY_SHA=#{SHA}"
    refute_includes command, "VPS_DEPLOY_PREFLIGHT_SHA"
  end

  def test_the_operator_surface_goes_through_the_preflight_for_remote_deploys
    source = File.read(File.expand_path("../bin/operator", __dir__))
    deploy = source[/when "deploy"\n.*?when "admin"/m]
    assert_includes deploy, "Operator::DeployPreflight.remote_command"
    assert_operator deploy.index("remote_command"), :<, deploy.index("ssh_run(command)")
  end
end
