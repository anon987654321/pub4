# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "fileutils"

class TestEvidenceTool < Minitest::Test
  SCRIPT = File.expand_path("../bin/evidence", __dir__)

  def setup
    @root = Dir.mktmpdir("evidence-tool-")
    git("init", "-q")
    git("config", "user.name", "Evidence Test")
    git("config", "user.email", "evidence-test@example.invalid")
    File.write(File.join(@root, "tracked.txt"), "tracked\n")
    git("add", "tracked.txt")
    git("commit", "-qm", "Initial test repository")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_records_pass_exit_status_commit_and_clean_state
    status, output = run_tool("pass", "--", RbConfig.ruby, "-e", "puts 'actual output'; exit 0")
    assert_equal 0, status.exitstatus, output
    artifact = latest_artifact("pass")
    assert_equal "PASS", artifact.fetch("verdict")
    assert_equal 0, artifact.fetch("command_exit_status")
    assert_equal git("rev-parse", "HEAD").strip, artifact.fetch("commit")
    assert_equal "clean", artifact.fetch("worktree")
    assert_includes File.read(File.join(@root, artifact.fetch("log"))), "actual output"
  end

  def test_preserves_blocked_exit_code
    status, output = run_tool("blocked", "--", RbConfig.ruby, "-e", "exit 77")
    assert_equal 77, status.exitstatus, output
    assert_equal "BLOCKED", latest_artifact("blocked").fetch("verdict")
  end

  def test_preserves_inconclusive_exit_code
    status, output = run_tool("unknown", "--", RbConfig.ruby, "-e", "exit 78")
    assert_equal 78, status.exitstatus, output
    assert_equal "INCONCLUSIVE", latest_artifact("unknown").fetch("verdict")
  end

  def test_timeout_terminates_command_and_records_timeout
    status, output = run_tool("timeout", "--timeout", "0.1", "--", RbConfig.ruby, "-e", "sleep 5")
    assert_equal 124, status.exitstatus, output
    artifact = latest_artifact("timeout")
    assert_equal "TIMEOUT", artifact.fetch("verdict")
    assert_equal true, artifact.fetch("timed_out")
    assert_operator artifact.fetch("duration_seconds"), :<, 3.0
  end

  def test_refuses_pass_override_for_nonzero_command
    status, output = run_tool("refused", "--verdict", "PASS", "--", RbConfig.ruby, "-e", "exit 1")
    assert_equal 1, status.exitstatus, output
    artifact = latest_artifact("refused")
    assert_equal "FAIL", artifact.fetch("verdict")
    assert_match(/PASS override refused/, artifact.fetch("verdict_override_rejected"))
  end

  def test_records_dirty_paths_and_sha256_for_attachments
    File.write(File.join(@root, "screenshot.txt"), "visual evidence\n")
    status, output = run_tool(
      "attach", "--attach", "screenshot.txt",
      "--note", "operator reviewed the screenshot",
      "--", RbConfig.ruby, "-e", "exit 0"
    )
    assert_equal 0, status.exitstatus, output
    artifact = latest_artifact("attach")
    assert_equal "dirty", artifact.fetch("worktree")
    assert_includes artifact.fetch("dirty_paths"), "screenshot.txt"
    assert_equal Digest::SHA256.hexdigest("visual evidence\n"), artifact.fetch("attachments").first.fetch("sha256")
    assert_equal ["operator reviewed the screenshot"], artifact.fetch("notes")
  end


  def test_requires_a_note_to_reclassify_a_successful_command
    status, output = run_tool("unexplained", "--verdict", "INCONCLUSIVE", "--", RbConfig.ruby, "-e", "exit 0")
    assert_equal 0, status.exitstatus, output
    artifact = latest_artifact("unexplained")
    assert_equal "PASS", artifact.fetch("verdict")
    assert_match(/requires a non-empty --note/, artifact.fetch("verdict_override_rejected"))
  end

  def test_records_explicit_manual_classification_with_note
    status, output = run_tool(
      "reviewed", "--verdict", "INCONCLUSIVE", "--note", "live browser unavailable on this host",
      "--", RbConfig.ruby, "-e", "exit 0"
    )
    assert_equal 0, status.exitstatus, output
    artifact = latest_artifact("reviewed")
    assert_equal "PASS", artifact.fetch("detected_verdict")
    assert_equal "INCONCLUSIVE", artifact.fetch("verdict")
    assert_equal ["live browser unavailable on this host"], artifact.fetch("notes")
  end

  def test_rejects_attachment_outside_repository
    outside = File.join(Dir.tmpdir, "outside-evidence-#{Process.pid}.txt")
    File.write(outside, "not part of repo")
    status, output = run_tool(
      "bad-attach", "--attach", outside, "--", RbConfig.ruby, "-e", "exit 0"
    )
    assert_equal 64, status.exitstatus, output
    refute File.directory?(File.join(@root, "evidence"))
  ensure
    File.delete(outside) if outside && File.file?(outside)
  end

  private

  def git(*args)
    out, status = Open3.capture2e("git", *args, chdir: @root)
    raise "git #{args.join(' ')} failed: #{out}" unless status.success?
    out
  end

  def run_tool(*args)
    output, status = Open3.capture2e(RbConfig.ruby, SCRIPT, *args, chdir: @root)
    [status, output]
  end

  def latest_artifact(label)
    path = Dir[File.join(@root, "evidence", "*-#{label}.json")].sort.last
    raise "missing artifact for #{label}" unless path
    JSON.parse(File.read(path))
  end
end
