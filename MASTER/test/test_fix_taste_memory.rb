# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../lib/fix/taste_memory"

class TestFixTasteMemory < Minitest::Test
  Taste = Master::Fix::TasteMemory

  def setup
    @root = Dir.mktmpdir
    @now = Time.at(1_800_000_000)
  end

  def teardown = FileUtils.remove_entry(@root)

  def memory = Taste.new(root: @root, clock: -> { @now })

  def test_summary_lists_approved_and_rejected_looks
    memory.record(surface: "brgen/posts_index/desktop", verdict: "approved", note: "calm column", changes: { "selectors" => [".feed"], "properties" => ["gap"] })
    memory.record(surface: "brgen/posts_show/mobile", verdict: "rejected", note: "too tight")

    text = memory.summary

    assert_match(/approved looks like: brgen index \(desktop\), selectors \.feed, properties gap, "calm column"/, text)
    assert_match(/rejected looks like: brgen show \(mobile\), "too tight"/, text)
  end

  def test_nothing_judged_says_nothing
    assert_nil memory.summary
  end

  def test_old_entries_decay_away
    memory.record(surface: "brgen/a_index/desktop", verdict: "approved")
    @now += 86_400 * 400

    assert_nil memory.summary
  end

  def test_file_is_capped
    (Taste::MAX_ENTRIES + 5).times { |n| memory.record(surface: "a/l#{n}/d", verdict: "approved") }

    assert_equal Taste::MAX_ENTRIES, JSON.parse(File.read(File.join(@root, "MASTER", Taste::PATH)))["entries"].size
  end

  def test_target_naming_an_app_ranks_that_app_first
    memory.record(surface: "amber/x_index/desktop", verdict: "approved", note: "amber one")
    memory.record(surface: "brgen/y_index/desktop", verdict: "approved", note: "brgen one")

    assert_operator memory.summary(target: "RAILS/brgen/app").index("brgen one"), :<, memory.summary(target: "RAILS/brgen/app").index("amber one")
  end

  def test_reject_also_teaches_repair_outcomes
    3.times { memory.reject(surface: "brgen/posts_index/desktop", note: "no") }

    assert_match(/avoid RENDERED_VISUAL_REFINEMENT \| taste:index \| RAILS\/brgen/, Master::Fix::RepairOutcomes.new(root: File.join(@root, "MASTER"), clock: -> { @now }).summary)
  end

  def test_changes_from_diff_reads_added_selectors_and_properties
    diff = "+++ b/x.scss\n+.feed {\n+  gap: 1rem;\n+  color: red;\n-  old: 1;\n"
    changes = Taste.changes_from_diff(diff)

    assert_equal [".feed"], changes["selectors"]
    assert_equal %w[gap color], changes["properties"]
  end

  def test_unknown_verdict_is_refused
    assert_raises(ArgumentError) { memory.record(surface: "a/b/c", verdict: "maybe") }
  end

  def test_orientation_carries_the_taste_lines
    FileUtils.mkdir_p(File.join(@root, "MASTER"))
    Taste.new(root: @root).record(surface: "brgen/posts_index/desktop", verdict: "approved", note: "calm")

    assert_includes Master::AI::Orientation.taste_memory(File.join(@root, "MASTER"), nil).to_s, "approved looks like"
  end
end
