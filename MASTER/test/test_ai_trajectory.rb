# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestAiTrajectory < Minitest::Test
  def test_operator_contract_is_available_from_master_load
    contract = Master::AI::OperatorContract

    assert_respond_to contract, :prompt
    assert_respond_to contract, :manifest
  end

  def test_ai_namespace_is_loaded_by_zeitwerk
    assert_equal "Master::AI", Master::AI.name
    assert_respond_to Master::AI::OperatorContract, :prompt
  end

  def test_operator_contract_is_compact_and_openbsd_shaped
    prompt = Master::AI::OperatorContract.prompt
    assert_includes prompt, "style: openbsd"
    assert_includes prompt, "shell: zsh"
    assert_includes prompt, "source tree"
    assert_includes prompt, "cross-tree reasoning"
    assert_includes prompt, "authority, topology, runtime"
    assert_includes prompt, "pinned source and lockfile"
    assert_includes prompt, "target man pages"
    assert_includes prompt, "interactive command shell: zsh"
    assert_includes prompt, "scripts follow their shebang"
    assert_includes prompt, "remote commands follow the verified target shell"
    assert_includes prompt, "target-release manuals"
    assert_includes prompt, "never assume GNU/Linux options or paths"
    assert_includes prompt, "read-only evidence first"
    assert_includes prompt, "preconditions, privilege, blast radius and recovery"
    refute_includes prompt, "shell execution: zsh only"
    assert_operator prompt.bytesize, :<, 4_000
  end

  def test_benchmark_rejects_linux_shell_reflexes
    record = {
      "task" => "fix a Ruby file",
      "model" => "ollama:qwen3.5:0.8b",
      "events" => [
        { "tool" => "Tree" },
        { "tool" => "ReadFile", "path" => "lib/a.rb" },
        { "tool" => "Shell", "command" => "bash -lc sed lib/a.rb" },
        { "tool" => "test" },
      ],
      "outcome" => "complete",
      "verified" => true,
    }
    score = Master::AI::Trajectory::Benchmark.score(record)
    refute score["checks"]["shell_abi"]
    assert_operator score["ratio"], :<, 1.0
  end

  def test_read_must_precede_write
    record = {
      "task" => "edit",
      "model" => "small-model",
      "events" => [
        { "tool" => "WriteFile", "path" => "lib/a.rb" },
        { "tool" => "ReadFile", "path" => "lib/a.rb" },
        { "tool" => "verify" },
      ],
      "outcome" => "complete",
      "verified" => true,
    }
    refute Master::AI::Trajectory::Benchmark.score(record)["checks"]["evidence"]
  end

  def test_verified_trajectory_round_trips
    Dir.mktmpdir("trajectory") do |dir|
      path = File.join(dir, "trajectory.ndjson")
      trajectory = Master::AI::Trajectory::Record.new(
        "task" => "map the tree",
        "model" => "small-model",
        "events" => [{ "tool" => "Tree" }, { "tool" => "verify" }],
        "outcome" => "complete",
        "verified" => true,
      )
      trajectory.append!(path)
      loaded = JSON.parse(File.read(path))
      assert_equal "master.llm.trajectory/v1", loaded["schema"]
      assert_equal "map the tree", loaded["task"]
      assert_equal 0o600, File.stat(path).mode & 0o777,
                   "trajectory prompts are opt-in private telemetry"
    end
  end

  def test_trajectory_log_rotates_to_a_bounded_tail
    Dir.mktmpdir("trajectory-rotation") do |dir|
      path = File.join(dir, "trajectory.ndjson")
      record = Master::AI::Trajectory::Record.new(
        "task" => "inspect",
        "model" => "small-model",
        "events" => [{ "tool" => "Tree" }],
        "outcome" => "complete",
        "verified" => true,
      )

      record.append!(path, max_bytes: 1)
      record.append!(path, max_bytes: 1)

      assert File.file?("#{path}.1")
      assert_operator File.size("#{path}.1"), :<=, 1
      assert_equal "inspect", JSON.parse(File.readlines(path).last)["task"]
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_trajectory_append_refuses_symlink_destination
    Dir.mktmpdir("trajectory-symlink") do |dir|
      target = File.join(dir, "target.ndjson")
      path = File.join(dir, "trajectory.ndjson")
      File.write(target, "keep\n")
      File.symlink(target, path)
      record = Master::AI::Trajectory::Record.new(
        "task" => "inspect",
        "model" => "small-model",
        "events" => [{ "tool" => "Tree" }],
        "outcome" => "complete",
        "verified" => true,
      )

      assert_raises(ArgumentError) { record.append!(path) }
      assert_equal "keep\n", File.read(target)
    end
  end

  def test_dataset_exports_only_verified_trajectories
    Dir.mktmpdir("trajectory") do |dir|
      input = File.join(dir, "in.ndjson")
      output = File.join(dir, "out.ndjson")
      good = {
        "task" => "inspect",
        "model" => "small-model",
        "events" => [{ "tool" => "Tree", "ok" => true }, { "tool" => "verify" }],
        "outcome" => "complete",
        "verified" => true,
      }
      bad = good.merge("verified" => false)
      File.write(input, [good, bad].map { |record| JSON.generate(record) }.join("\n") + "\n")

      assert_equal 1, Master::AI::Trajectory::Dataset.export(input:, output:)
      lines = File.readlines(output, chomp: true)
      assert_equal 1, lines.size
      exported = JSON.parse(lines.first)
      assert_equal "master.llm.sft/v1", exported["schema"]
    end
  end
end
