# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"
require "open3"
require "rbconfig"

class TestRunJournalLifecycle < Minitest::Test
  class RecordingBus
    attr_reader :events
    attr_accessor :failure

    def initialize
      @events = []
    end

    def publish_required(name, payload = {})
      raise IOError, "simulated required audit failure" if name == failure

      @events << [name, payload]
      self
    end

    def publish(_name, **_payload)
      self
    end
  end

  def start_journal(root, bus)
    Master::Fix::RunJournal.new(root:, bus:).start_or_resume(
      target: File.join(root, "MASTER"),
      files: [File.join(root, "private.rb")],
      max_passes: 2,
      budget_seconds: 60
    )
  end

  def test_architecture_tournament_report_survives_journal_reconstruction_and_is_checksum_verified
    Dir.mktmpdir("master-architecture-journal") do |root|
      bus = RecordingBus.new
      journal = Master::Fix::RunJournal.new(root:, bus:)
      run = start_journal(root, bus)
      candidate = { "id" => "AX01", "title" => "Keep current boundaries", "score" => 77,
                    "scorecard" => { "source_evidence" => 20 }, "runtime_tests" => "NOT_RUN" }
      report = {
        "schema_version" => 2, "target" => "MASTER", "status" => "RUNNING",
        "requested_candidates_per_tree" => 30,
        "targets" => [{ "tree" => "MASTER", "status" => "COMPLETE", "requested" => 30,
                         "accepted" => 30, "qualified" => 10, "candidates" => Array.new(30, candidate),
                         "evidence_manifest" => [{ "path" => "MASTER/lib/owner.rb", "sha256" => "a" * 64 }] }],
        "brief" => "Runtime tests: NOT_RUN."
      }
      provenance = { "source_digest" => "a" * 64, "scope_digest" => "b" * 64,
                     "law_digest" => "c" * 64, "identity_digest" => "d" * 64 }
      receipt = journal.persist_architecture_report(run.fetch("id"), target: File.join(root, "MASTER"), report:, provenance:)

      assert receipt.fetch("readback_verified")
      assert_match(%r{\A\.master/fix_architecture/}, receipt.fetch("path"))
      path = File.join(root, receipt.fetch("path"))
      assert_equal 0, File.stat(path).mode & 0o077
      restored = Master::Fix::RunJournal.new(root:, bus:).verify_architecture_report(run.fetch("id"))
      assert_equal "verified", restored.fetch("status")
      assert_equal 30, restored.fetch("report").fetch("targets").first.fetch("candidates").size
      assert_equal provenance, restored.fetch("provenance")

      File.write(path, "tampered\n")
      assert_equal "checksum_mismatch", Master::Fix::RunJournal.new(root:, bus:).verify_architecture_report(run.fetch("id")).fetch("status")
    end
  end

  def test_architecture_checkpoint_survives_a_real_child_process_exit
    Dir.mktmpdir("master-architecture-process-boundary") do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER"))
      script = <<~'RUBY'
        require "json"
        require "master"
        require "fix/run_journal"

        class ProcessBoundaryBus
          def publish_required(*) = self
          def publish(*) = self
        end

        root = ARGV.fetch(0)
        journal = Master::Fix::RunJournal.new(root:, bus: ProcessBoundaryBus.new)
        run = journal.start_or_resume(
          target: File.join(root, "MASTER"), files: [], max_passes: 2, budget_seconds: 60
        )
        provenance = {
          "source_digest" => "a" * 64, "scope_digest" => "b" * 64,
          "law_digest" => "c" * 64, "identity_digest" => "d" * 64
        }
        report = {
          "schema_version" => 2, "target" => "MASTER", "status" => "RUNNING",
          "requested_candidates_per_tree" => 30,
          "targets" => [{
            "tree" => "MASTER", "status" => "COMPLETE", "requested" => 30,
            "accepted" => 30, "qualified" => 0, "winner" => nil,
            "candidates" => [], "evidence_manifest" => []
          }],
          "brief" => "Interrupted after one checkpoint."
        }
        journal.persist_architecture_report(
          run.fetch("id"), target: File.join(root, "MASTER"), report:, provenance:
        )
        puts JSON.generate("run_id" => run.fetch("id"))
      RUBY

      output, status = Open3.capture2e(
        RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", script, root,
        chdir: Master::ROOT
      )
      assert status.success?, "checkpoint writer process failed: #{output}"
      run_id = JSON.parse(output.lines.last).fetch("run_id")

      restored = Master::Fix::RunJournal.new(root:, bus: RecordingBus.new).verify_architecture_report(run_id)

      assert_equal "verified", restored.fetch("status")
      assert_equal "RUNNING", restored.dig("report", "status")
      assert_equal "Interrupted after one checkpoint.", restored.dig("report", "brief")
    end
  end

  def test_journal_persistence_is_bracketed_by_required_metadata_events
    Dir.mktmpdir("master-journal-audit") do |root|
      bus = RecordingBus.new
      run = start_journal(root, bus)
      events = bus.events.select { |name, _| name.start_with?("fix:journal_lifecycle:") }

      assert_equal %w[fix:journal_lifecycle:before fix:journal_lifecycle:after], events.map(&:first)
      assert_equal events.first.last.fetch(:audit_id), events.last.last.fetch(:audit_id)
      assert_equal "persist", events.first.last.fetch(:operation)
      assert_equal "ok", events.last.last.fetch(:status)
      assert_equal 1, events.last.last.fetch(:item_count)
      assert File.file?(File.join(root, ".master", "fix_runs.json"))
      refute File.exist?(File.join(root, ".master", ".fix_runs.pending"))
      refute_includes events.inspect, "private.rb"
      refute_empty run.fetch("id")
    end
  end

  def test_missing_before_event_prevents_journal_write
    Dir.mktmpdir("master-journal-before-failure") do |root|
      bus = RecordingBus.new
      bus.failure = "fix:journal_lifecycle:before"

      error = assert_raises(IOError) { start_journal(root, bus) }

      assert_match(/required audit failure/, error.message)
      refute File.exist?(File.join(root, ".master", "fix_runs.json"))
      refute File.exist?(File.join(root, ".master", ".fix_runs.pending"))
    end
  end

  def test_missing_after_event_leaves_marker_and_blocks_resume
    Dir.mktmpdir("master-journal-after-failure") do |root|
      bus = RecordingBus.new
      bus.failure = "fix:journal_lifecycle:after"

      assert_raises(IOError) { start_journal(root, bus) }

      journal_path = File.join(root, ".master", "fix_runs.json")
      marker_path = File.join(root, ".master", ".fix_runs.pending")
      before = File.binread(journal_path)
      assert File.file?(marker_path)

      error = assert_raises(RuntimeError) do
        start_journal(root, RecordingBus.new)
      end

      assert_match(/lifecycle audit is incomplete/, error.message)
      assert_equal before, File.binread(journal_path), "resume must not mutate an ambiguously audited journal"
      assert File.file?(marker_path)
    end
  end
  def gone_pid
    pid = Process.spawn("true")
    Process.wait(pid)
    pid
  end

  def plant_marker(root, pid)
    path = File.join(root, ".master", ".fix_runs.pending")
    File.write(path, JSON.generate(pid:, subject: "deadrun", operation: "persist") + "\n")
    path
  end

  def test_marker_left_by_a_gone_process_is_cleared_and_the_run_proceeds
    Dir.mktmpdir("master-journal-dead-marker") do |root|
      first = start_journal(root, RecordingBus.new)
      marker = plant_marker(root, gone_pid)

      out, = capture_io { @run = start_journal(root, RecordingBus.new) }

      refute File.exist?(marker), "a gone writer's marker must not wedge every later run"
      assert_match(%r{cleared \.master/\.fix_runs\.pending left by gone pid=\d+ subject=deadrun}, out)
      assert_equal first.fetch("id"), @run.fetch("id")
      assert @run.fetch("resumed")
    end
  end

  def test_marker_held_by_a_live_process_still_refuses
    Dir.mktmpdir("master-journal-live-marker") do |root|
      start_journal(root, RecordingBus.new)
      journal_path = File.join(root, ".master", "fix_runs.json")
      before = File.binread(journal_path)
      marker = plant_marker(root, Process.pid)

      error = assert_raises(RuntimeError) { start_journal(root, RecordingBus.new) }

      assert_match(/lifecycle audit is incomplete/, error.message)
      assert File.file?(marker)
      assert_equal before, File.binread(journal_path)
    end
  end

end
