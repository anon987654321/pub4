# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# The smoke boots the real container and builds the FixLoop. Unit tests that
# stub the loop cannot see a reader of a method that no longer exists.
class TestBootSmoke < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def run_smoke(env = {})
    Open3.capture2e(
      { "MASTER_QUIET" => "1" }.merge(env),
      File.join(ROOT, "bin", "ruby"), File.join(ROOT, "tools", "boot_smoke.rb"),
      chdir: ROOT
    )
  end

  def test_builds_the_fix_loop_without_running_a_fix
    out, status = run_smoke
    assert status.success?, out
    assert_match(/boot_smoke: FixLoop built, max_passes=\d+ clean_runs=\d+ plateau_window=\d+/, out)
  end

  def test_the_check_profiles_run_the_smoke
    check = File.read(File.join(ROOT, "bin", "check"))
    assert_includes check, "boot_smoke.rb"
  end

  def test_pre_push_runs_the_smoke
    hook = File.read(File.join(ROOT, "..", "OPENBSD", "dev", "githooks", "pre-push"))
    assert_includes hook, "boot_smoke.rb"
  end
end
