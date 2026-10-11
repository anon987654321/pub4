# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "master"

class TestMemoryReview < Minitest::Test
  def setup
    @root = Dir.mktmpdir("master-memory-review")
    @memory = Master::Ground::Memory.new(root: @root)
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def evidence(source, body = source)
    { source:, sha256: Digest::SHA256.hexdigest(body) }
  end

  def test_review_is_provenanced_and_preserves_audit_history
    @memory.remember("deployment_target", "vm23", source: "operator:conversation", confidence: 0.9)
    result = @memory.review("deployment_target", verdict: :confirmed,
                            evidence: evidence("test:review", "checked target"), reviewer: "operator")

    assert_equal "confirmed", result.fetch("status")
    assert_equal "operator", result.fetch("reviews").last.fetch("reviewer")
    assert_equal "vm23", @memory.recall("deployment_target")
  end

  def test_contradicted_memory_is_not_used_for_context_or_search
    @memory.remember("deploy_target", "obsolete host", source: "old note", confidence: 0.8)
    @memory.review("deploy_target", verdict: :contradicted,
                   evidence: evidence("test:contradiction"), reviewer: "operator")

    refute @memory.context_eligible?("deploy_target")
    refute @memory.keyword_recall("obsolete host", top_n: 10).any? { |row| row[:key] == "deploy_target" }
    assert_equal "obsolete host", @memory.recall("deploy_target"), "review preserves the auditable original"
  end

  def test_obsolete_memory_is_excluded_from_consolidated_context
    @memory.remember("old_preference", "use the old route", source: "operator", confidence: 0.8)
    @memory.review("old_preference", verdict: :obsolete,
                   evidence: evidence("test:expiry"), reviewer: "operator")

    refute_includes @memory.context_summary.to_s, "old_preference"
  end

  def test_review_requires_evidence_and_known_verdict
    @memory.remember("fact", "value")
    assert_raises(ArgumentError) do
      @memory.review("fact", verdict: :confirmed, evidence: { source: "review", sha256: "bad" }, reviewer: "operator")
    end
    assert_raises(ArgumentError) do
      @memory.review("fact", verdict: :guess, evidence: evidence("review"), reviewer: "operator")
    end
  end
end
