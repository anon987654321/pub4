# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../lib/fix/repair_outcomes"

class TestFixRepairOutcomes < Minitest::Test
  Outcomes = Master::Fix::RepairOutcomes

  def setup
    @root = Dir.mktmpdir
    @now = Time.at(1_800_000_000)
  end

  def teardown = FileUtils.remove_entry(@root)

  def outcomes = Outcomes.new(root: @root, clock: -> { @now })

  def test_rejected_class_is_listed_to_avoid_and_accepted_to_work
    4.times { outcomes.record("#{@root}/RAILS/brgen/app/a.rb", %w[CQS], { consensus_rejected: 1 }) }
    3.times { outcomes.record("#{@root}/RAILS/amber/app/b.rb", %w[GUARD], { applied: 1 }) }

    text = outcomes.summary

    assert_match(/avoid CQS \| rb \| RAILS\/brgen: 4 rejected\/reverted, mostly consensus_rejected/, text)
    assert_match(/works GUARD \| rb \| RAILS\/amber: 3 accepted/, text)
  end

  def test_reverts_count_against_a_class
    3.times { outcomes.record("#{@root}/x/a.rb", %w[L], { rejected: 1 }) }

    assert_match(/avoid L/, outcomes.summary)
  end

  def test_too_little_evidence_says_nothing
    outcomes.record("#{@root}/x/a.rb", %w[L], { rejected: 1 })

    assert_nil outcomes.summary
  end

  def test_old_entries_decay_away
    4.times { outcomes.record("#{@root}/x/a.rb", %w[L], { rejected: 1 }) }
    @now += 14 * 86_400

    assert_nil outcomes.summary, "one half-life leaves weight 2, under the avoid line"
    @now += 80 * 86_400
    outcomes.record("#{@root}/x/a.rb", %w[M], { applied: 1 })
    refute_includes File.read(File.join(@root, Outcomes::PATH)), "\"L |"
  end

  def test_size_is_bounded
    (Outcomes::MAX_CLASSES + 30).times { |i| outcomes.record("#{@root}/x/a.rb", ["LAW#{i}"], { rejected: 1 }) }

    assert_operator JSON.parse(File.read(File.join(@root, Outcomes::PATH)))["classes"].size, :<=, Outcomes::MAX_CLASSES
  end

  def test_summary_is_byte_bounded
    30.times { |i| 4.times { outcomes.record("#{@root}/x/a.rb", ["A_LONG_LAW_NAME_#{i}" * 3], { rejected: 1 }) } }

    assert_operator outcomes.summary.bytesize, :<=, Outcomes::SUMMARY_BYTES
  end

  def test_orientation_carries_the_summary
    4.times { outcomes.record("#{@root}/x/a.rb", %w[CQS], { rejected: 1 }) }
    require_relative "../lib/ai/orientation"

    assert_includes Master::AI::Orientation.send(:repair_history, @root).to_s, "avoid CQS"
  end

  def test_repair_memory_feeds_it
    require_relative "../lib/fix/repair_memory"
    path = File.join(@root, "a.rb")
    File.write(path, "x = 1\n")
    3.times { Master::Fix::RepairMemory.new(root: @root).record(path, %w[CQS], { reflexion_rejected: 1 }) }

    assert_match(/avoid CQS/, Outcomes.new(root: @root).summary)
  end
end
