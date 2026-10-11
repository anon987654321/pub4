# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "operator/fix_status"

class TestFixStatus < Minitest::Test
  def setup
    @root = Dir.mktmpdir("fix-status-")
    FileUtils.mkdir_p(File.join(@root, "MASTER", ".master"))
  end

  def teardown = FileUtils.rm_rf(@root)

  def write(path, body)
    File.write(File.join(@root, "MASTER", ".master", path), body)
  end

  def run_record(target, state: "active", pid: Process.pid)
    {
      "id" => "abcdef0123456789", "state" => state, "target" => File.join(@root, target),
      "files" => %w[a.rb b.rb], "max_passes" => 7, "pid" => pid, "started_at" => "2026-10-11T10:00:00Z",
      "passes" => [{ "pass" => 1, "state" => "done" }, { "pass" => 2, "state" => "active" }]
    }
  end

  def test_queue_follows_the_order_the_trees_were_typed
    assert_equal %w[RAILS STUDIO], Operator::FixStatus.queue_from("bin/master /fix RAILS STUDIO")
    assert_equal %w[STUDIO MASTER], Operator::FixStatus.queue_from("bin/master /fix STUDIO MASTER STUDIO")
    assert_equal %w[RAILS], Operator::FixStatus.queue_from("bin/master /fix RAILS")
    assert_empty Operator::FixStatus.queue_from("bin/master /fix RAILS/brgen/app")
  end

  def test_single_tree_is_one_target_and_many_follow_argument_order
    root = "/tmp/pub4"
    registry = Master::CLI::CommandRegistry

    assert_equal ["RAILS"], registry.send(:fix_targets, "RAILS", root:)
    reversed = registry.send(:fix_targets, "STUDIO RAILS", root:)
    assert_equal %w[STUDIO RAILS].map { |tree| File.join(root, tree) }, reversed
  end

  def test_reads_the_journal_mission_and_logs_without_writing
    runs = [run_record("RAILS"), run_record("STUDIO", state: "crashed", pid: 0)]
    write("fix_runs.json", JSON.generate("version" => 1, "runs" => runs))
    mission = { "state" => "running", "stage" => "execute", "scope" => "RAILS",
                "attempt_count" => 2, "artifacts" => %w[x] }
    write("mission.json", JSON.generate(mission))
    write("fix-RAILS.log", "first\nlast line\n")
    before = Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH).sort

    payload = Operator::FixStatus.new(root: @root).payload

    assert_equal %w[RAILS STUDIO], payload[:runs].map { |row| row[:tree] }
    rails = payload[:runs].first
    assert_equal [2, 7, 2, true], [rails[:pass], rails[:max_passes], rails[:files], rails[:alive]]
    assert_equal "last line", payload[:logs].first[:last]
    assert_equal 2, payload[:mission][:attempts]
    assert_equal before, Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH).sort
  end

  def test_trees_filter_narrows_runs_logs_and_mission
    write("fix_runs.json", JSON.generate("runs" => [run_record("RAILS"), run_record("STUDIO")]))
    write("mission.json", JSON.generate("state" => "running", "scope" => "STUDIO"))
    write("fix-RAILS.log", "r\n")
    write("fix-STUDIO.log", "s\n")

    payload = Operator::FixStatus.new(root: @root, trees: %w[RAILS]).payload

    assert_equal %w[RAILS], payload[:runs].map { |row| row[:tree] }
    assert_equal %w[fix-RAILS.log], payload[:logs].map { |row| row[:name] }
    assert_nil payload[:mission]
  end

  def test_render_names_the_empty_cases
    text = Operator::FixStatus.new(root: @root).render

    assert_includes text, "none in the journal"
    assert_includes text, "mission: none"
  end
end
