# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"
require_relative "../lib/fix/fix_loop"

# The 2026-11-05 RAILS run asked for MOBILE_FIRST+NO_ASCII_LINE_ART+SMALL_FILES+LINE_HEIGHT_ON_SCALE+
# TOUCH_TARGET_MIN in one proposal over a 2,800-line stylesheet, and the verifier refused the diff.
class TestProposalScope < Minitest::Test
  Scope = Master::Fix::ProposalScope

  def finding(law, line) = { law:, line:, message: law, file: "_brgen_shared_overrides.scss" }

  # The laws and lines the run bundled, from its scan of _brgen_shared_overrides.scss.
  def bundled
    [finding("NO_ASCII_LINE_ART", 6), finding("NO_ASCII_LINE_ART", 8), finding("SMALL_FILES", 1),
     finding("LINE_HEIGHT_ON_SCALE", 541), finding("TOUCH_TARGET_MIN", 681), finding("LINE_HEIGHT_ON_SCALE", 865),
     finding("MOBILE_FIRST", 913), finding("MOBILE_FIRST", 1083), finding("TOUCH_TARGET_MIN", 1671),
     finding("MOBILE_FIRST", 1815), finding("LINE_HEIGHT_ON_SCALE", 1950), finding("LINE_HEIGHT_ON_SCALE", 1956)]
  end

  def test_a_proposal_takes_one_scope_window_and_leaves_the_rest
    taken, deferred = Scope.narrow(bundled)

    lines = taken.map { |row| row[:line] }
    assert_operator lines.max - lines.min, :<=, Scope::WINDOW
    refute_includes taken.map { |row| row[:law] }, "SMALL_FILES"
    assert_equal bundled.size, taken.size + deferred.size
  end

  def test_adjacent_findings_of_several_laws_still_share_one_proposal
    near = [finding("MAGIC_COLOR", 474), finding("CONTRAST_TOKENS", 474), finding("EIGHT_PX_RHYTHM", 480)]

    taken, deferred = Scope.narrow(near + [finding("MOBILE_FIRST", 2400)])

    assert_equal near, taken
    assert_equal [2400], deferred.map { |row| row[:line] }
  end

  def test_a_whole_file_law_goes_alone_after_the_windows
    groups = Scope.groups([finding("SMALL_FILES", 1), finding("SQUINT_TEST", 1), finding("MOBILE_FIRST", 3)])

    laws = groups.map { |group| group.map { |row| row[:law] } }
    assert_equal [["MOBILE_FIRST"], ["SMALL_FILES"], ["SQUINT_TEST"]], laws
  end

  # The stream's FileRepair is handed the window only.
  class Host
    include Master::Fix::FixLoop::PassRunner::StreamStage

    Memory = Struct.new(:recorded) do
      def sync_detectors(_rules) = nil
      def fresh(_path, findings) = findings
      def record(*) = nil
    end

    Rule = Struct.new(:id)

    def initialize = @root = "/repo"
    def repair_memory = @repair_memory ||= Memory.new
    def repair_context(_path) = { complete: true, files: [] }
    def tally_rule_results(*, **) = 0
    def go(rows) = repair_file("/repo/a.scss", rows, rows.map { |row| Rule.new(row[:law]) }.uniq, "a.scss",
                               Master::Fix::FixLoop::PassRunner::StreamStage::Stream.new(Set.new, 1, Hash.new(0)))
  end

  def test_the_stream_hands_file_repair_one_window
    asked = nil

    fake = Object.new
    fake.define_singleton_method(:run) { |_path| { fixed: 0, breakdown: {} } }
    fake.define_singleton_method(:asked_rules) { [] }
    fake.define_singleton_method(:scope) { nil }
    build = lambda do |**options|
      asked = options[:findings]
      fake
    end
    Master::Fix::FileRepair.stub(:new, build) { Host.new.go(bundled) }

    lines = asked.map { |row| row[:line] }
    assert_operator lines.max - lines.min, :<=, Scope::WINDOW
  end
end
