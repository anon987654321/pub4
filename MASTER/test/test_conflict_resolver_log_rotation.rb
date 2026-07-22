# frozen_string_literal: true

require_relative "test_helper"

class TestConflictResolverLogRotation < Minitest::Test
  # conflict_log.jsonl was append-only with no cap and grew to 890MB
  # (alongside activity.jsonl's 1.2GB -- together they filled the disk and
  # crashed an in-progress /fix round). Same fix as EventLog: rotate aside
  # before appending once oversized, never read the whole file to do it.
  def test_log_conflict_rotates_an_oversized_log_instead_of_growing_forever
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      path = File.join(dir, Master::Fix::ConflictResolver::LOG_PATH)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "x" * (Master::Fix::ConflictResolver::LOG_MAX_BYTES + 1))

      resolver.send(:log_conflict, rule_a: "A", rule_b: "B", resolution: "a_wins", file: "f.rb", line: 1)

      assert File.exist?("#{path}.1"), "oversized log should be rotated aside, not appended to"
      assert File.exist?(path), "a fresh log file should exist after rotation"
      assert_operator File.size(path), :<, Master::Fix::ConflictResolver::LOG_MAX_BYTES
    end
  end

  def test_log_conflict_under_the_size_cap_does_not_rotate
    Dir.mktmpdir do |dir|
      resolver = Master::Fix::ConflictResolver.new(root: dir, config: {})
      path = File.join(dir, Master::Fix::ConflictResolver::LOG_PATH)

      resolver.send(:log_conflict, rule_a: "A", rule_b: "B", resolution: "a_wins", file: "f.rb", line: 1)

      refute File.exist?("#{path}.1"), "a small log should never rotate"
      assert File.exist?(path)
    end
  end
end
