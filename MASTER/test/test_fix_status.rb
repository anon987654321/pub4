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
    FileUtils.mkdir_p(File.join(@root, ".master"))
  end

  def teardown = FileUtils.rm_rf(@root)

  def write(path, body)
    File.write(File.join(@root, "MASTER", ".master", path), body)
  end

  # /fix keeps its mission at the repository root, its journal under MASTER.
  def write_mission(body)
    File.write(File.join(@root, ".master", "mission.json"), body)
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
    write_mission(JSON.generate(mission))
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

  def test_status_and_tail_share_the_stream_and_show_the_latest_heartbeat
    beat = "fix0: pass 2/8 scan0 files 812/2638 (31%) fixes 1 ok 0 failed tokens = 5 (5) elapsed = 60s (1m00s) eta ~3m load 1.0"
    write("fix-RAILS.log", "#{beat.sub("812", "700")}\nscan0: 9/10 a.rb\n#{beat}\nbudget0: spent\n")

    status = Operator::FixStatus.new(root: @root)

    assert_equal beat, status.payload[:heartbeat]
    assert_includes status.render, "heartbeat: #{beat}"
    out = StringIO.new
    require "operator/fix_tail"
    Operator::FixTail.run(%w[--once --tail=2], roots: [File.join(@root, "MASTER")], io: out)
    assert_equal "#{beat}\nbudget0: spent\n", out.string
  end

  def test_status_exposes_terminal_reason_and_bounded_convergence_receipt
    run = run_record("RAILS", state: "validation_failed", pid: 0).merge(
      "message" => "validation failed:\nrendered output differs",
      "finished_at" => "2026-10-17T20:45:00Z",
      "evidence" => {
        "observations" => 3, "files_observed" => 42, "findings" => 7,
        "quality_delta" => 0.125, "finding_digest" => "a" * 64,
        "snapshot_digest" => "b" * 64, "authority_digest" => "c" * 64
      },
    )
    write("fix_runs.json", JSON.generate("version" => 1, "runs" => [run]))

    status = Operator::FixStatus.new(root: @root)
    row = status.payload[:runs].first
    rendered = status.render

    assert_equal "validation_failed", row[:state]
    assert_equal "validation failed: rendered output differs", row[:message]
    assert_equal "2026-10-17T20:45:00Z", row[:finished]
    assert_includes row[:receipt], "observations=3"
    assert_includes row[:receipt], "files=42"
    assert_includes row[:receipt], "finding=aaaaaaaaaaaa"
    assert_includes row[:receipt], "snapshot=bbbbbbbbbbbb"
    assert_includes rendered, "result: validation failed: rendered output differs"
    assert_includes rendered, "receipt: recorded"
    assert_includes rendered, "finished: 2026-10-17T20:45:00Z"
    refute_match(/deployment validation passed/i, rendered)
  end

  def test_trees_filter_narrows_runs_logs_and_mission
    write("fix_runs.json", JSON.generate("runs" => [run_record("RAILS"), run_record("STUDIO")]))
    write_mission(JSON.generate("state" => "running", "scope" => "STUDIO"))
    write("fix-RAILS.log", "r\n")
    write("fix-STUDIO.log", "s\n")

    payload = Operator::FixStatus.new(root: @root, trees: %w[RAILS]).payload

    assert_equal %w[RAILS], payload[:runs].map { |row| row[:tree] }
    assert_equal %w[fix-RAILS.log], payload[:logs].map { |row| row[:name] }
    assert_nil payload[:mission]
  end

  def test_corrupt_journals_are_not_reported_as_empty
    write("fix_runs.json", "{not valid json")
    write_mission("{also broken")

    status = Operator::FixStatus.new(root: @root)
    payload = status.payload
    rendered = status.render

    assert_match(/invalid JSON:/, payload[:read_errors].fetch(Operator::FixStatus::JOURNAL))
    assert_match(/invalid JSON:/, payload[:read_errors].fetch(Operator::FixStatus::MISSION))
    assert_includes rendered, "unavailable (invalid JSON:"
    assert_includes rendered, "mission: unavailable (invalid JSON:"
    refute_includes rendered, "none in the journal"
    refute_match(/mission: none\z/, rendered)
  end

  def test_status_refuses_symlinked_journal_and_mission_files
    Dir.mktmpdir do |outside|
      external = File.join(outside, "payload.json")
      File.write(external, JSON.generate("version" => 1, "runs" => [run_record("RAILS")]))
      File.symlink(external, File.join(@root, "MASTER", ".master", "fix_runs.json"))
      File.symlink(external, File.join(@root, ".master", "mission.json"))

      payload = Operator::FixStatus.new(root: @root).payload

      assert_equal "refusing symlink", payload[:read_errors][Operator::FixStatus::JOURNAL]
      assert_equal "refusing symlink", payload[:read_errors][Operator::FixStatus::MISSION]
      assert_empty payload[:runs]
      assert_nil payload[:mission]
    end
  end

  def test_render_names_the_empty_cases
    text = Operator::FixStatus.new(root: @root).render

    assert_includes text, "none in the journal"
    assert_includes text, "mission: none"
  end
end
