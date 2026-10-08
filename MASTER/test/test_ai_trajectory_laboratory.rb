# frozen_string_literal: true

require_relative "test_helper"
require "json"
require_relative "../lib/ai/trajectory/laboratory"

class TestTrajectoryLaboratory < Minitest::Test
  def test_groups_models_and_scores_verified_work
    Dir.mktmpdir("trajectory-lab") do |dir|
      path = File.join(dir, "trajectories.ndjson")
      rows = [
        {
          "task" => "good",
          "model" => "model-a",
          "events" => [{ "tool" => "Tree" }, { "tool" => "verify" }],
          "outcome" => "complete",
          "verified" => true,
        },
        {
          "task" => "bad",
          "model" => "model-b",
          "events" => [{ "tool" => "ReadFile" }],
          "outcome" => "blocked",
          "verified" => false,
        },
      ]
      File.write(path, rows.map { |row| JSON.generate(row) }.join("
") + "
")
      result = Master::AI::Trajectory::Laboratory.summarize(input: path)
      assert_equal 1, result["model-a"][:calls]
      assert_equal 1, result["model-a"][:verified]
      assert_equal 1, result["model-b"][:calls]
      assert_equal 0, result["model-b"][:verified]
      assert_operator result["model-a"][:benchmark_ratio], :>, result["model-b"][:benchmark_ratio]
    end
  end
end
