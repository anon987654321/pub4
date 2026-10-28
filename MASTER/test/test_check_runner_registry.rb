# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "yaml"
require "open3"
require "rbconfig"

class TestCheckRunnerRegistry < Minitest::Test
  MASTER_ROOT = File.expand_path("..", __dir__)
  REPOSITORY_ROOT = File.expand_path("../..", __dir__)
  RUNNER = File.join(MASTER_ROOT, "checks", "runner.rb")

  def run_registry(registry)
    Dir.mktmpdir("check-registry-contract") do |dir|
      registry_path = File.join(dir, "checks.yml")
      ledger_path = File.join(dir, "ledger.jsonl")
      File.write(registry_path, YAML.dump(registry))
      output, status = Open3.capture2e(
        { "CHECKS_FILE" => registry_path, "CHECK_LEDGER" => ledger_path,
          "CHECK_AUTOFIX" => "0" },
        RbConfig.ruby, RUNNER, "--all", chdir: REPOSITORY_ROOT
      )
      yield output, status
    end
  end

  def test_registry_rejects_rows_that_declare_both_class_and_script
    run_registry(
      "ambiguous" => { "class" => "Deploy::CheckResult", "script" => "architecture.rb" }
    ) do |output, status|
      refute status.success?
      assert_includes output, "must declare exactly one of class: or script:"
    end
  end

  def test_registry_rejects_script_paths_that_escape_checks_tree
    run_registry("bad_script" => { "script" => "../README.md" }) do |output, status|
      refute status.success?
      assert_includes output, "script: parent or absolute paths are not allowed"
    end
  end

  def test_registry_rejects_require_paths_that_escape_declared_tree
    run_registry(
      "bad_require" => { "require" => "../../README.md", "class" => "Deploy::CheckResult" }
    ) do |output, status|
      refute status.success?
      assert_includes output, "require: parent or absolute paths are not allowed"
    end
  end

  def test_registry_rejects_absolute_script_paths
    run_registry("bad_script" => { "script" => File.join(Dir.tmpdir, "arbitrary.rb") }) do |output, status|
      refute status.success?
      assert_includes output, "script: parent or absolute paths are not allowed"
    end
  end
end
