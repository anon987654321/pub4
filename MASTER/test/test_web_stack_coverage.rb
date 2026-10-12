# frozen_string_literal: true

require_relative "test_helper"

class TestWebStackCoverage < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  MASTER_ROOT = File.expand_path("..", __dir__)
  WEB_TEST_ROOT = File.join(REPO_ROOT, "RAILS", "master_web", "test")

  def test_master_ci_runs_the_rails_web_and_rack_ui_suites
    source = File.read(File.join(MASTER_ROOT, "bin", "check"))

    assert_includes source, 'rake["test:web"]'
    assert_includes source, 'rake["test:web_ui"]'
    assert_includes source, "ci_steps << web_node_step"
  end

  def test_node_suite_uses_the_canonical_recursive_web_test_inventory
    source = File.read(File.join(MASTER_ROOT, "bin", "check"))
    discovered = Dir[File.join(WEB_TEST_ROOT, "**/*.test.mjs")].sort

    refute_empty discovered, "RAILS/master_web has JavaScript runtime tests that must run"
    assert_includes source, 'File.join(ROOT, "..", "RAILS", "master_web", "test")'
    assert_includes source, 'Dir[File.join(web_test_dir, "**/*.test.mjs")].sort'
    refute_includes source, 'File.join(ROOT, "web/test/*.test.mjs")',
                    "the old MASTER/web path does not exist and silently selects nothing"
    assert_includes discovered.map { |path| File.basename(path) }, "face_boot.test.mjs"
  end

  def test_missing_node_or_an_empty_javascript_inventory_is_not_a_green_ci_step
    source = File.read(File.join(MASTER_ROOT, "bin", "check"))

    assert_includes source, "web ui behaviour unavailable"
    assert_includes source, "exit 3"
    assert_includes source, "Node.js unavailable; web behavior was not measured"
  end
end
