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
    { source:, content: body, sha256: Digest::SHA256.hexdigest(body) }
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
    @memory.remember("_consolidated_summary", "Prior summary repeats the old route")
    @memory.review("old_preference", verdict: :obsolete,
                   evidence: evidence("test:expiry"), reviewer: "operator")

    refute_includes @memory.context_summary.to_s, "old_preference"
    refute_includes @memory.context_summary.to_s, "Prior summary repeats the old route"
  end

  def test_contradicted_structured_preferences_and_reasoning_stay_out_of_context
    preference_key = @memory.remember_preference(
      { domain: "music", preference: "use sparse arrangements", source: "operator" },
      key: "preference/music",
    )
    @memory.review(preference_key, verdict: :contradicted,
                   evidence: evidence("review:music"), reviewer: "operator")
    assert_empty @memory.preferences(limit: 10)

    reasoning_key = @memory.remember_reasoning(
      { claim: "old assumption", selected: "discard", source: "test:reasoning" },
      key: "reasoning/old",
    )
    @memory.review(reasoning_key, verdict: :obsolete,
                   evidence: evidence("review:reasoning"), reviewer: "operator")
    assert_empty @memory.reasoning(limit: 10)
    refute_includes @memory.reasoning_context.to_s, "old assumption"
  end

  def test_legacy_scalar_memories_remain_searchable
    @memory.instance_variable_get(:@store)["legacy_scalar"] = "remember the quiet route"

    assert @memory.context_eligible?("legacy_scalar")
    assert @memory.keyword_recall("quiet route", top_n: 10).any? { |row| row[:key] == "legacy_scalar" }
  end

  def test_fts5_search_excludes_contradicted_memories
    skip "sqlite3 gem unavailable" unless defined?(SQLite3::Database)

    previous_search = ENV["MASTER_MEMORY_SEARCH"]
    previous_zero = ENV["MASTER_ZERO_EMBEDDINGS"]
    ENV["MASTER_MEMORY_SEARCH"] = "fts5"
    ENV["MASTER_ZERO_EMBEDDINGS"] = "1"
    @memory.remember("obsolete_deploy_host", "obsolete deploy host silver harbor", source: "legacy")
    @memory.review("obsolete_deploy_host", verdict: :contradicted,
                   evidence: evidence("test:fts-review", "reviewed host"), reviewer: "operator")

    refute @memory.fts5_recall("obsolete deploy host silver harbor", top_n: 10).any? { |row| row[:key] == "obsolete_deploy_host" }
  ensure
    ENV["MASTER_MEMORY_SEARCH"] = previous_search
    ENV["MASTER_ZERO_EMBEDDINGS"] = previous_zero
  end

  def test_legacy_scalar_memory_can_be_reviewed_without_losing_its_text
    @memory.instance_variable_get(:@store)["legacy_scalar"] = "legacy route preference"
    result = @memory.review(
      "legacy_scalar",
      verdict: :obsolete,
      evidence: evidence("test:legacy-scalar", "reviewed legacy value"),
      reviewer: "operator",
    )

    assert_equal "obsolete", result.fetch("status")
    assert_equal "legacy route preference", @memory.recall("legacy_scalar")
    refute @memory.context_eligible?("legacy_scalar")
    refute @memory.keyword_recall("legacy route preference", top_n: 10).any? { |row| row[:key] == "legacy_scalar" }
  end

  def test_review_recovers_from_malformed_legacy_provenance
    @memory.remember("legacy_fact", "a remembered value")
    entry = @memory.instance_variable_get(:@store).fetch("legacy_fact")
    entry["provenance"] = "corrupted"
    result = @memory.review("legacy_fact", verdict: :uncertain,
                            evidence: evidence("test:legacy"), reviewer: "operator")

    assert_equal "uncertain", result.fetch("status")
    assert_equal "legacy", result.fetch("source")
    assert_equal "a remembered value", @memory.recall("legacy_fact")
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

  # Retention: an entry untouched for longer than TTL_DAYS leaves the live
  # store for archive/, keeping its value; a fresh entry stays where it is.
  def test_entries_past_retention_move_to_the_archive_and_fresh_ones_stay
    @memory.remember("old_fact", "kept for the audit trail")
    @memory.remember("fresh_fact", "still current")
    store = @memory.instance_variable_get(:@store)
    store["old_fact"]["ts"] = Time.now.to_i - ((Master::Ground::Memory::TTL_DAYS + 1) * 86_400)

    @memory.send(:prune_stale!)

    refute store.key?("old_fact")
    assert_equal "kept for the audit trail", store.fetch("archive/old_fact").fetch("value")
    assert store.key?("fresh_fact")
  end
end
