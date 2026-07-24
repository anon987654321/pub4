# frozen_string_literal: true

require_relative "test_helper"

class TestConflictResolverPriority < Minitest::Test
  # reject_higher_priority? had no test coverage before it was switched from
  # a plain Severity.rank comparison to the blended Priority.score (severity
  # + law priority + quality) -- these pin down the behavior that switch was
  # supposed to preserve for the common case, plus the log side effect.
  def test_rejects_when_a_strictly_more_severe_finding_is_introduced
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      original = { rule: "STYLE_RULE", severity: "warning" }
      before = []
      after = [{ "rule" => "SAFETY_RULE", "severity" => "critical", "line" => 5 }]

      assert resolver.reject_higher_priority?(original_violation: original, before:, after:, path: "f.rb")

      log_path = File.join(dir, Master::Fix::ConflictResolver::LOG_PATH)
      assert File.exist?(log_path), "a rejection should be logged"
      assert_includes File.read(log_path), "SAFETY_RULE"
    end
  end

  def test_does_not_reject_when_introduced_finding_is_not_more_severe
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      original = { rule: "SAFETY_RULE", severity: "critical" }
      before = []
      after = [{ "rule" => "STYLE_RULE", "severity" => "warning", "line" => 5 }]

      refute resolver.reject_higher_priority?(original_violation: original, before:, after:, path: "f.rb")
    end
  end

  def test_does_not_reject_when_nothing_new_was_introduced
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      original = { rule: "STYLE_RULE", severity: "warning" }
      finding = { "rule" => "SAFETY_RULE", "severity" => "critical", "line" => 5 }

      refute resolver.reject_higher_priority?(original_violation: original, before: [finding], after: [finding], path: "f.rb")
    end
  end
end
