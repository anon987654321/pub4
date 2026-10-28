# frozen_string_literal: true

require_relative "test_helper"
require "content"
require "fileutils"

# The content machine: a kanban whose cards cross lanes only through
# verdicts. These tests pin the loop — a card the judge rejects goes back
# with notes, a card the rubric admits publishes, and the board survives a
# reload with the same state.
class TestContentMachine < Minitest::Test
  def setup
    @root = File.join(Dir.tmpdir, "content_test_#{Process.pid}")
    FileUtils.mkdir_p(@root)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_card_flows_to_publishable_and_the_board_persists
    machine = Master::Content::Machine.new(root: @root, judge: lenient_judge)
    machine.enqueue(title: "Run the checks", brief: "How a contributor verifies a change",
                    audience: "new contributor")
    3.times do
      break if machine.run.include?("publishable=1")
    end
    card = machine.board.cards.first
    assert_equal :publishable, card.lane

    reloaded = Master::Content::Board.new(root: @root)
    assert_equal 1, reloaded.publishable_count, "the board must survive a reload"
    assert_equal :publishable, reloaded.cards.first.lane
  end

  def test_the_judge_sends_thin_work_back_until_the_cycle_cap
    machine = Master::Content::Machine.new(root: @root, judge: strict_judge)
    machine.enqueue(title: "Thin piece", brief: "Not enough substance", audience: "reader")
    machine.run
    machine.run
    machine.run
    card = machine.board.cards.first
    assert_equal :publishable, card.lane, "the cycle cap must stop an endless loop"
    assert_equal Master::Content::Machine::MAX_CYCLES_PER_CARD - 1,
                 card.reviews.count { |review| review["verdict"] == "revise" }
  end

  def test_revise_notes_carry_the_reason
    card = Master::Content::Card.new(title: "T", brief: "B", audience: "A", body: "short")
    verdict, notes = Master::Content::Judge.new.judge(card)
    assert_equal :revise, verdict
    assert notes.any? { |note| note.include?("thin") }, notes.inspect
  end

  def test_lanes_are_the_five_the_board_names
    assert_equal %i[backlog writing editing judging publishable], Master::Content::Card::LANES
  end

  private

  def lenient_judge
    judge = Master::Content::Judge.new(min_words: 5)
    def judge.judge(card)
      card.body.to_s.empty? ? [:revise, ["empty"]] : [:publish, []]
    end
    judge
  end

  def strict_judge
    judge = Master::Content::Judge.new(min_words: 5)
    def judge.judge(_card)
      [:revise, ["not good enough"]]
    end
    judge
  end
end
