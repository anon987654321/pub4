# frozen_string_literal: true

require "minitest/autorun"
require_relative "../tools/require_graph"

class TestRequireRelativeTargets < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_every_literal_require_relative_resolves
    report = Operator::RequireGraph.run(root: ROOT)

    assert report["clean"], "broken imports:\n#{report["broken"].map { |row|
      "#{row["file"]}:#{row["line"]}: #{row["require_relative"]} -> #{row["target"]}"
    }.join("\n")}"
  end

  def test_all_three_first_party_trees_are_scanned
    report = Operator::RequireGraph.run(root: ROOT)

    assert_operator report["scanned"], :>, 1500
  end
end
