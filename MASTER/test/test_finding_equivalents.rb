# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

# Two instruments reporting one problem on one line become one finding, decided once.
class TestFindingEquivalents < Minitest::Test
  def resolver(root) = Master::Fix::ConflictResolver.new(root:)

  def test_a_rubocop_line_length_merges_into_long_line_on_the_same_line
    Dir.mktmpdir do |root|
      rows = [{ law: "LONG_LINE", file: "a.rb", line: 3, message: "line 130 chars (max 120)" },
              { law: "rubocop", file: "a.rb", line: 3, message: "rubocop: Layout/LineLength — Line is too long." },
              { law: "rubocop", file: "a.rb", line: 9, message: "rubocop: Layout/LineLength — Line is too long." }]

      kept = resolver(root).filter_findings(rows)

      assert_equal [%w[LONG_LINE 3], %w[rubocop 9]], kept.map { |row| [row["law"], row["line"].to_s] }
      assert_equal ["rubocop:Layout/LineLength"], kept.first["also"]
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
