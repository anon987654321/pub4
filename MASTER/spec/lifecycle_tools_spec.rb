# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

class LifecycleToolsSpec < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read_tool(name)
    File.read(File.join(ROOT, "bin", name))
  end

  def test_doctor_reports_ok_fail_lines
    output, = Open3.capture3(
      { "MASTER_KEYLESS" => "1" },
      RbConfig.ruby,
      File.join(ROOT, "bin", "doctor"),
      chdir: ROOT,
    )

    assert_includes output, "MASTER doctor"
    assert_match(/^(?:OK|FAIL) yaml:/, output)
    assert_match(/^OK (?:ruby|git):/, output)
    assert_match(/^(?:OK|FAIL) [a-z-]+:/, output)
  end

  def test_smoke_web_waits_for_bootstrap
    source = read_tool("smoke-web")
    assert_includes source, "smoke-web"
    assert_includes source, "wait for bootstrap"
    assert_includes source, "MASTER_SMOKE_WEB_WARM_S"
    assert_includes source, "cache_efficiency"
  end

  def test_onboard_writes_master_config_yml
    source = read_tool("onboard")
    assert_includes source, "config.yml"
    assert_includes source, "--no-interactive"
    assert_includes source, "SecureRandom.hex"
  end

  def test_cleanup_is_dry_run_by_default
    source = read_tool("cleanup")
    assert_includes source, "dry-run only"
    assert_includes source, "--apply"
    assert_includes source, "working tree dirty"
  end

  def test_cleanup_writes_audit_reports
    source = read_tool("cleanup")
    assert_includes source, "reports"
    assert_includes source, "repo_inventory.rb"
    assert_includes source, "history_valuables.rb"
  end

  # repo_inventory reports anything at the repo root that is not on one of its
  # two allowlists, so a stale list is wrong in both directions at once: it
  # excuses what is gone and reports what belongs. Both had gone stale — five of
  # seven files and four of six directories named subjects that do not exist,
  # while MASTER, RAILS, OPENBSD and STUDIO were reported as non-canonical
  # top-level directories. Held against the tree rather than a fixture, because
  # the tree is what the tool reads.
  def test_the_root_allowlists_name_the_repo_root_exactly
    load_inventory
    repo = File.expand_path("..", ROOT)
    # The tool own reading rather than a second one beside it: root_entries
    # drops what git ignores, and a spec that re-derived the list from
    # Dir.children failed on .DS_Store and the gate ledger while the tool was
    # right.
    present = root_entries
    files, dirs = present.partition { |name| File.file?(File.join(repo, name)) }

    assert_equal files.sort, Object.const_get(:ALLOWED_ROOT_FILES).sort,
                 "repo_inventory's ALLOWED_ROOT_FILES and the repo root have drifted"
    assert_equal dirs.sort, Object.const_get(:ALLOWED_ROOT_DIRS).sort,
                 "repo_inventory's ALLOWED_ROOT_DIRS and the repo root have drifted"
  end

  private

  # The tool is a script with top-level constants and a `$PROGRAM_NAME` guard, so
  # loading it defines them here and runs nothing.
  def load_inventory
    load File.join(ROOT, "tools", "repo_inventory.rb")
  end
end
