# frozen_string_literal: true

# A document that names a file nobody can open reads as current and sends the
# reader somewhere empty. DEPLOY/ became RAILS/ and four documents kept pointing
# at the dead tree; the root CLAUDE.md was deleted for exactly that drift, and
# amber's architecture record was deleted without anything noticing because
# nothing read it.
#
# This reads them. Every backticked path in every markdown file under MASTER,
# RAILS and OPENBSD must resolve, except the entries in
# data/doc_baselines.yml (doc_paths:), each of which carries its reason.

require "minitest/autorun"
require "yaml"
require_relative "../tools/doc_paths"

class TestDocPaths < Minitest::Test
  BASELINE = File.expand_path("../data/doc_baselines.yml", __dir__)

  # One scan for the whole class; setup runs per test and the scan reads every
  # document in three trees.
  def self.report = @report ||= Pub4::DocPaths.run

  def setup
    @report = self.class.report
    @baseline = YAML.safe_load_file(BASELINE).fetch("doc_paths")
  end

  def test_no_undocumented_dead_paths
    unexpected = @report[:findings].filter_map do |doc, tokens|
      allowed = (@baseline[doc] || []).map { |row| row.fetch("path") }
      extra = tokens - allowed
      "#{doc}: #{extra.join(', ')}" if extra.any?
    end

    assert_empty unexpected,
                 "documents naming paths that do not exist. Fix the reference, or add it to " \
                 "MASTER/data/doc_baselines.yml (doc_paths:) with a reason:\n  #{unexpected.join("\n  ")}"
  end

  # A baseline that outlives its finding is the same defect one level up: a
  # declaration nothing reads. An entry that stops being dead must leave.
  def test_baseline_has_no_stale_entries
    stale = @baseline.filter_map do |doc, rows|
      found = @report[:findings][doc] || []
      gone = rows.map { |row| row.fetch("path") } - found
      "#{doc}: #{gone.join(', ')}" if gone.any?
    end

    assert_empty stale,
                 "baseline entries that now resolve — remove them from " \
                 "MASTER/data/doc_baselines.yml (doc_paths:):\n  #{stale.join("\n  ")}"
  end

  def test_every_baseline_entry_states_a_reason
    missing = @baseline.flat_map do |doc, rows|
      rows.reject { |row| row["why"].to_s.strip.length > 20 }.map { |row| "#{doc}: #{row['path']}" }
    end

    assert_empty missing, "baseline entries without a reason: #{missing.join(', ')}"
  end

  # The checker is the thing most likely to be wrong. Prove it still resolves a
  # path that exists and still flags one that does not.
  def test_the_checker_measures_something
    assert Pub4::DocPaths.resolve("MASTER/tools/doc_paths.rb", "MASTER/DEBT.md"),
           "checker fails to resolve a path that exists"
    refute Pub4::DocPaths.resolve("MASTER/tools/no_such_file_here.rb", "MASTER/DEBT.md"),
           "checker resolves a path that does not exist"
    assert_operator @report[:checked], :>, 200,
                    "checker examined #{@report[:checked]} paths — it stopped seeing the documents"
  end
end
