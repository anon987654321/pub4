# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestConflictResolverPriority < Minitest::Test
  def test_priority_resolution_uses_the_active_root
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "laws.yml"), {
        "HIGH_RULE" => { "priority" => 1, "principle" => "high", "violates_law" => "HIGH_RULE" },
        "LOW_RULE" => { "priority" => 3, "principle" => "low", "violates_law" => "LOW_RULE" }
      }.to_yaml)

      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})

      assert resolver.reject_higher_priority?(
        original_violation: { rule: "LOW_RULE", severity: "warning" },
        before: [],
        after: [{ "rule" => "HIGH_RULE", "severity" => "warning", "line" => 5 }],
        path: "f.rb"
      )
    end
  end

  # An edit above a standing finding moves it to another line and restamps the file's
  # fingerprint. That finding is not new, so it must not block a repair.
  def test_a_standing_finding_that_moved_is_not_introduced
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      before = [{ "law" => "SAFETY_RULE", "severity" => "critical", "line" => 40, "fingerprint" => "aaa", "message" => "unsafe call" }]
      after = [{ "law" => "SAFETY_RULE", "severity" => "critical", "line" => 25, "fingerprint" => "bbb", "message" => "unsafe call" }]
      original = { law: "STYLE_RULE", severity: "warning" }

      refute resolver.reject_higher_priority?(original_violation: original, before:, after:, path: "f.rb")
      assert_empty resolver.send(:findings_introduced, before:, after:, path: "f.rb")
    end
  end

  def test_a_second_copy_of_a_standing_finding_is_introduced
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      row = { "law" => "SAFETY_RULE", "severity" => "critical", "message" => "unsafe call" }
      before = [row.merge("line" => 40)]
      after = [row.merge("line" => 41), row.merge("line" => 7)]
      original = { law: "STYLE_RULE", severity: "warning" }

      assert_equal 1, resolver.send(:findings_introduced, before:, after:, path: "f.rb").size
      assert resolver.reject_higher_priority?(original_violation: original, before:, after:, path: "f.rb")
    end
  end

  def test_conflict_policy_uses_the_active_root_when_not_injected
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "soul.yml"), "negotiable:
  conflict_resolution:
    strategy: root_local
")

      resolver = Master::Fix::ConflictResolver.new(root: dir)
      config = resolver.instance_variable_get(:@config)

      assert_equal "root_local", config.fetch("strategy")
    end
  end

  # reject_higher_priority? had no test coverage before it was switched from
  # a plain Severity.rank comparison to the blended Priority.score (severity
  # + law priority + quality) -- these pin down the behavior that switch was
  # supposed to preserve for the common case, plus the log side effect.
  def test_rejects_when_a_strictly_more_severe_finding_is_introduced
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      original = { law: "STYLE_RULE", severity: "warning" }
      before = []
      after = [{ "law" => "SAFETY_RULE", "severity" => "critical", "line" => 5 }]

      assert resolver.reject_higher_priority?(original_violation: original, before:, after:, path: "f.rb")

      log_path = File.join(dir, Master::Fix::ConflictResolver::LOG_PATH)
      assert File.exist?(log_path), "a rejection should be logged"
      assert_includes File.read(log_path), "SAFETY_RULE"
    end
  end

  def test_does_not_reject_when_introduced_finding_is_not_more_severe
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      original = { law: "SAFETY_RULE", severity: "critical" }
      before = []
      after = [{ "law" => "STYLE_RULE", "severity" => "warning", "line" => 5 }]

      refute resolver.reject_higher_priority?(original_violation: original, before:, after:, path: "f.rb")
    end
  end

  def test_does_not_reject_when_nothing_new_was_introduced
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      original = { law: "STYLE_RULE", severity: "warning" }
      finding = { "law" => "SAFETY_RULE", "severity" => "critical", "line" => 5 }

      refute resolver.reject_higher_priority?(original_violation: original, before: [finding], after: [finding], path: "f.rb")
    end
  end
end
