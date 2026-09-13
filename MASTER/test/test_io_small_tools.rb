# frozen_string_literal: true

require_relative "test_helper"

# Two small tool surfaces the agent can reach: FeedbackRecord writes to the
# learnings ledger, and Clean runs OPENBSD/dev/clean.sh under a governor and a
# time budget.
class TestIoSmallTools < Minitest::Test
  Governor = Struct.new(:answer) do
    def permit?(_name, _tier, _detail) = answer
  end

  Learnings = Struct.new(:events) do
    def record_event(**event) = events << event
  end

  def test_feedback_record_validates_then_records
    learnings = Learnings.new([])
    tool = Master::Io::FeedbackRecord.new(learnings:)

    assert tool.call(event_type: "tool_success", dimension: " scan ", value: "2", metadata: :x).ok?
    assert_equal [{ event_type: "tool_success", dimension: " scan ", value: 2.0, metadata: "x" }], learnings.events
    assert_equal :validation, tool.call(event_type: "made_up", dimension: "scan").category
    assert_equal :validation, tool.call(event_type: "tool_failure", dimension: "  ").category
    assert_equal 1, learnings.events.size
  end

  def test_clean_strips_trailing_space_and_collapses_blank_runs
    root = Dir.mktmpdir("clean_")
    File.write(File.join(root, "a.txt"), "one   \n\n\n\ntwo\t\n")
    result = Master::Io::Clean.new(root:, governor: Governor.new(Master::Result.ok("ok"))).call

    refute result.err?, (result.message if result.err?)
    assert_equal "one\n\ntwo\n", File.read(File.join(root, "a.txt"))
    assert_match(/cleaned 1 file/, result.value!)
  ensure
    FileUtils.rm_rf(root)
  end

  def test_clean_refuses_a_missing_path_and_honours_the_governor
    root = Dir.mktmpdir("clean_")
    File.write(File.join(root, "a.txt"), "x  \n")
    denied = Master::Result.err("no", category: :policy)

    assert_equal :validation, Master::Io::Clean.new(root:, governor: Governor.new(denied)).call(path: "nope").category
    assert_same denied, Master::Io::Clean.new(root:, governor: Governor.new(denied)).call
    assert_equal "x  \n", File.read(File.join(root, "a.txt"))
  ensure
    FileUtils.rm_rf(root)
  end
end
