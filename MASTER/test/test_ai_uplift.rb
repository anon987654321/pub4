# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestAiUplift < Minitest::Test
  def test_operator_contract_is_compact_and_openbsd_shaped
    prompt = Master::AI::OperatorContract.prompt
    assert_includes prompt, "style: openbsd"
    assert_includes prompt, "shell: zsh"
    assert_includes prompt, "source tree"
    assert_operator prompt.bytesize, :<, 4_000
  end

  def test_benchmark_rejects_linux_shell_reflexes
    record = {
      "task" => "fix a Ruby file",
      "model" => "ollama:gemma3:4b",
      "events" => [
        { "tool" => "Tree" },
        { "tool" => "ReadFile", "path" => "lib/a.rb" },
        { "tool" => "Shell", "command" => "bash -lc sed lib/a.rb" },
        { "tool" => "test" }
      ],
      "outcome" => "complete",
      "verified" => true
    }
    score = Master::AI::Uplift::Benchmark.score(record)
    refute score["checks"]["shell_abi"]
    assert_operator score["ratio"], :<, 1.0
  end

  def test_read_must_precede_write
    record = {
      "task" => "edit",
      "model" => "gemma",
      "events" => [
        { "tool" => "WriteFile", "path" => "lib/a.rb" },
        { "tool" => "ReadFile", "path" => "lib/a.rb" },
        { "tool" => "verify" }
      ],
      "outcome" => "complete",
      "verified" => true
    }
    refute Master::AI::Uplift::Benchmark.score(record)["checks"]["evidence"]
  end

  def test_verified_trajectory_round_trips
    Dir.mktmpdir("gemma") do |dir|
      path = File.join(dir, "trajectory.ndjson")
      trajectory = Master::AI::Uplift::Trajectory.new(
        "task" => "map the tree",
        "model" => "gemma",
        "events" => [{ "tool" => "Tree" }, { "tool" => "verify" }],
        "outcome" => "complete",
        "verified" => true
      )
      trajectory.append!(path)
      loaded = JSON.parse(File.read(path))
      assert_equal "master.gemma.trajectory/v1", loaded["schema"]
      assert_equal "map the tree", loaded["task"]
    end
  end

  def test_dataset_exports_only_verified_trajectories
    Dir.mktmpdir("gemma") do |dir|
      input = File.join(dir, "in.ndjson")
      output = File.join(dir, "out.ndjson")
      good = {
        "task" => "inspect",
        "model" => "gemma",
        "events" => [{ "tool" => "Tree" }, { "tool" => "verify" }],
        "outcome" => "complete",
        "verified" => true
      }
      bad = good.merge("verified" => false)
      File.write(input, [good, bad].map { |record| JSON.generate(record) }.join("\n") + "\n")

      assert_equal 1, Master::AI::Uplift::Dataset.export(input:, output:)
      lines = File.readlines(output, chomp: true)
      assert_equal 1, lines.size
      exported = JSON.parse(lines.first)
      assert_equal "master.gemma.sft/v1", exported["schema"]
    end
  end
end
