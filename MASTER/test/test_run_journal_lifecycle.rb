# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

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
end
