# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "net/http"

# Three small tool surfaces the agent can reach: FeedbackRecord writes to the
# learnings ledger, Clean runs OPENBSD/dev/clean.sh under a governor and a time
# budget, and BrgenBridge reads brgen's internal status over loopback.
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

  def test_brgen_bridge_needs_its_token_before_it_opens_a_socket
    ENV.delete("MASTER_INTERNAL_TOKEN")
    opened = false
    result = Net::HTTP.stub(:start, ->(*) { opened = true }) { Master::Io::BrgenBridge.status }

    assert_equal :validation, result.category
    refute opened
  end

  def test_brgen_bridge_summary_asks_once_and_renders_the_counts
    calls = 0
    body = { "city" => "bergen", "generated_at" => "now", "marketplace_listings" => 3 }.to_json
    response = Struct.new(:code, :body).new("200", body)
    with_token do
      summary = Net::HTTP.stub(:start, lambda { |*|
        calls += 1
        response
      }) { Master::Io::BrgenBridge.summary }

      assert_match(/\Aok: brgen tenant=bergen at now\nmarketplace_listings=3 /, summary)
    end
    assert_equal 1, calls, "one summary is one status request"
  end

  def test_brgen_bridge_reports_a_non_200_as_infrastructure
    response = Struct.new(:code, :body).new("503", "")
    with_token do
      result = Net::HTTP.stub(:start, ->(*) { response }) { Master::Io::BrgenBridge.status }

      assert_equal "brgen: internal status 503", result.message
    end
  end

  def with_token
    previous = ENV["MASTER_INTERNAL_TOKEN"]
    ENV["MASTER_INTERNAL_TOKEN"] = "t"
    yield
  ensure
    previous.nil? ? ENV.delete("MASTER_INTERNAL_TOKEN") : ENV["MASTER_INTERNAL_TOKEN"] = previous
  end
end
