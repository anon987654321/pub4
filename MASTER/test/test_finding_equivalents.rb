# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

# Two instruments reporting one problem on one line become one finding, decided once.
class TestFindingEquivalents < Minitest::Test
  def resolver(root) = Master::Fix::ConflictResolver.new(root:)

  # Metrics/AbcSize is the one linter twin still on: stricter (20) than the
  # ABC_SIZE ratchet (40). Where both fire on a line they are one finding; where
  # only the cop fires, it stands alone.
  def test_a_rubocop_abc_size_merges_into_abc_size_on_the_same_line
    Dir.mktmpdir do |root|
      rows = [{ law: "ABC_SIZE", file: "a.rb", line: 3, message: "ABC size 52.1 for #call (ratchet 40)" },
              { law: "rubocop", file: "a.rb", line: 3, message: "rubocop: Metrics/AbcSize — Assignment Branch Condition size is too high." },
              { law: "rubocop", file: "a.rb", line: 9, message: "rubocop: Metrics/AbcSize — Assignment Branch Condition size is too high." }]

      kept = resolver(root).filter_findings(rows)

      assert_equal [%w[ABC_SIZE 3], %w[rubocop 9]], kept.map { |row| [row["law"], row["line"].to_s] }
      assert_equal ["rubocop:Metrics/AbcSize"], kept.first["also"]
    end
  end

  # The priority filter may still drop the lower law; the merge itself never joins them.
  def test_unrelated_laws_on_one_line_are_not_merged
    Dir.mktmpdir do |root|
      rows = [{ law: "LONG_LINE", file: "a.rb", line: 3, message: "long" },
              { law: "VERTICAL_BREATH", file: "a.rb", line: 3, message: "suffocated" }]

      assert(resolver(root).filter_findings(rows).none? { |row| row.key?("also") })
    end
  end
end
