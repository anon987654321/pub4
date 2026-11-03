# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

# The refutation ledger (data/proposals.yml) converges a loop only while every
# refuted row keeps what makes it one: the claim it answers, the reason it was
# wrong and the evidence that settled it. The file's header is the contract;
# these tests hold the file to it. Deleting a refuted row is the move the
# header forbids — it re-enters the loop as a fresh idea — so the MASTER
# retirements of 2026-11-03 are pinned here by id.
class TestProposalsLedger < Minitest::Test
  LEDGER = File.expand_path("../data/proposals.yml", __dir__)

  RETIREMENTS = %w[
    capability-feature-flags
    target-stack-auto-detection
    multi-temperature-best-of-n
    slack-webhook-notifications
    okr-style-self-scoring
    coverage-percentage-gate
  ].freeze

  def test_rows_are_unique_and_the_ledger_keeps_its_memory
    rows = YAML.safe_load_file(LEDGER, aliases: false).fetch("proposals")
    assert_operator rows.size, :>=, 20
    ids = rows.map { |row| row.fetch("id") }
    assert_equal ids.uniq.size, ids.size
  end

  def test_every_refuted_row_carries_claim_reason_and_evidence
    rows = YAML.safe_load_file(LEDGER, aliases: false).fetch("proposals")
    rows.select { |row| row.fetch("state") == "refuted" }.each do |row|
      id = row.fetch("id")
      refute_empty row["claim"].to_s.strip, "#{id} is refuted without its claim"
      refute_empty row["reason"].to_s.strip, "#{id} is refuted without its reason"
      refute_empty row["refuted_by"].to_s.strip, "#{id} is refuted without evidence"
    end
  end

  def test_the_master_retirements_stay_refuted
    rows = YAML.safe_load_file(LEDGER, aliases: false).fetch("proposals")
    RETIREMENTS.each do |id|
      row = rows.find { |candidate| candidate.fetch("id") == id }
      refute_nil row, "#{id} was deleted from the refutation ledger"
      assert_equal "refuted", row.fetch("state"), "#{id} was retired with a reason and stays refuted"
      refute_empty row["reason"].to_s.strip, "#{id} lost its reason"
      refute_empty row["refuted_by"].to_s.strip, "#{id} lost its evidence"
    end
  end
end
