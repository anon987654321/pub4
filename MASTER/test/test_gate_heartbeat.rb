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

  def test_scanner_progress_names_the_pass_law_file_and_active_work
    Dir.mktmpdir do |dir|
      path = File.join(dir, "p.json")
      File.write(path, JSON.generate(
        "kind" => "scan", "state" => "running", "pass" => "structural",
        "law" => "NO_GOD_CLASS", "file" => "MASTER/lib/master.rb",
        "checks" => 184, "active" => 8, "n" => 5, "total" => 43,
        "at" => 990.0, "updated_at" => 1000.0
      ))
      now = [0.0]
      lines = []
      beat = heartbeat(path, lines, now:, wall: 1000.0)

      now[0] = 4.9
      assert_nil beat.beat
      now[0] = 5.0
      line = beat.beat

      assert_includes line, "pass=structural"
      assert_includes line, "law=NO_GOD_CLASS"
      assert_includes line, "file=MASTER/lib/master.rb"
      assert_includes line, "checks=184"
      assert_includes line, "active=8"
      assert_includes line, "laws=5/43"
      assert_includes line, "check elapsed 10s"
      assert_includes line, "stage elapsed 5s"
    end
  end

  def test_stale_scanner_progress_is_reported_as_stale_not_running
    Dir.mktmpdir do |dir|
      path = File.join(dir, "p.json")
      File.write(path, JSON.generate(
        "kind" => "scan", "state" => "running", "pass" => "semantic",
        "law" => "MEANINGFUL_NAMES", "file" => "MASTER/lib/master.rb",
        "checks" => 9, "active" => 1, "n" => 1, "total" => 20,
        "at" => 990.0, "updated_at" => 1000.0
      ))
      now = [0.0]
      lines = []
      beat = heartbeat(path, lines, now:, wall: 1010.0)
      now[0] = 5.0

      line = beat.beat
      assert_includes line, "scan progress stale"
      assert_includes line, "last update 10s ago"
      assert_includes line, "stage elapsed 5s"
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
