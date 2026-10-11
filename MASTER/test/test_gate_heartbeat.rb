# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "tmpdir"
require_relative "../lib/operator/gate_heartbeat"

class TestGateHeartbeat < Minitest::Test
  def heartbeat(path, lines, now:, wall: 1000.0)
    Operator::GateHeartbeat.new(label: "rails gates", path:, cadence: 28, clock: -> { now.first },
                                wall: -> { wall }, say: ->(text) { lines << text })
  end

  def test_names_the_gate_and_elapsed_at_the_28_second_cadence
    Dir.mktmpdir do |dir|
      path = File.join(dir, "p.json")
      File.write(path, JSON.generate("n" => 7, "total" => 41, "name" => "css_constitution", "at" => 940.0))
      now = [0.0]
      lines = []
      beat = heartbeat(path, lines, now:)

      now[0] = 27.0
      assert_nil beat.beat
      now[0] = 28.0
      assert_equal "rails gates gate 7/41 css_constitution running 1m00s, elapsed 28s", beat.beat
      now[0] = 40.0
      assert_nil beat.beat
      now[0] = 56.0
      assert beat.beat
      assert_equal 2, lines.size
    end
  end

  def test_without_progress_it_still_speaks
    Dir.mktmpdir do |dir|
      now = [0.0]
      lines = []
      beat = heartbeat(File.join(dir, "none.json"), lines, now:)
      now[0] = 30.0
      beat.beat
      assert_equal ["rails gates running, elapsed 30s"], lines
    end
  end

  def test_around_hands_the_block_a_progress_path_for_the_runner
    Operator::GateHeartbeat.around("rails gates", poll: 0) do |env|
      assert_equal [Operator::GateHeartbeat::ENV_KEY], env.keys
    end
  end

  def test_runner_writes_the_gate_in_hand
    Dir.mktmpdir do |dir|
      path = File.join(dir, "p.json")
      gates = File.join(dir, "gates.yml")
      File.write(gates, "absent_gate:\n  script: no_such_script.rb\n")
      env = { "GATE_PROGRESS_FILE" => path, "GATES_FILE" => gates, "GATE_LEDGER" => File.join(dir, "ledger.jsonl") }
      Open3.capture2e(env, RbConfig.ruby, File.expand_path("../gates/runner.rb", __dir__), "--all")

      row = JSON.parse(File.read(path))
      assert_equal [1, 1, "absent_gate"], row.values_at("n", "total", "name")
    end
  end
end
