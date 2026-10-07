# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/ai/orientation"
require_relative "../lib/fix/wishlist"
require "tmpdir"
require "fileutils"

class TestFixWishlist < Minitest::Test
  class RecordingAgent
    attr_reader :prompts

    def initialize(reply)
      @reply = reply
      @prompts = []
    end

    def ask(prompt)
      @prompts << prompt
      @reply
    end
  end

  def setup
    @root = Dir.mktmpdir("wishlist_")
    FileUtils.mkdir_p(File.join(@root, "lib"))
    File.write(File.join(@root, "lib", "sample.rb"), "module Sample\nend\n")
    @bus = Class.new do
      attr_reader :events
      def initialize = @events = []
      def publish(event, payload = {}) = @events << { event:, payload: }
    end.new
  end

  def teardown = FileUtils.rm_rf(@root)

  def reply
    (1..24).map do |i|
      "- id: wish_#{i}\n  title: Wish #{i}\n  rationale: improve something measurable\n  anchor: lib/sample.rb:1\n  change: make the next improvement explicit\n  effort: cheap\n  reversibility: reversible\n  implementation: next_fix\n  evidence: sample.rb is present in the oriented tree"
    end.join("\n")
  end

  def test_call_writes_a_bounded_evidence_linked_report
    agent = RecordingAgent.new(reply)
    result = Master::Fix::Wishlist.new(root: @root, agent:, event_bus: @bus).call(state: "done", target: @root, run_id: "r1")

    assert_equal "wishlist: drafted 24 item(s) → runtime/wishlist.md", result
    report = File.read(File.join(@root, "runtime", "wishlist.md"))
    assert_includes report, "# MASTER wishlist"
    assert_includes report, "### 1. Wish 1"
    assert_includes report, "### 24. Wish 24"
    assert_includes report, "anchor: lib/sample.rb:1"
    assert_includes @bus.events.map { |e| e[:event] }, "wishlist:done"
  end

  def test_invalid_file_anchors_are_dropped_without_losing_the_valid_queue
    bad = reply.dup
    4.times { bad = bad.sub("anchor: lib/sample.rb:1", "anchor: lib/missing.rb:99") }
    agent = RecordingAgent.new(bad)
    result = Master::Fix::Wishlist.new(root: @root, agent:).call(state: "done", target: @root, run_id: "r2")

    assert_equal "wishlist: drafted 20 item(s) → runtime/wishlist.md", result
  end

  def test_pending_context_exposes_full_next_fix_proposals
    agent = RecordingAgent.new(reply)
    Master::Fix::Wishlist.new(root: @root, agent:).call(state: "done", target: @root, run_id: "r3")

    context = Master::Fix::Wishlist.pending_context(@root, limit: 2)
    assert_includes context, "Pending wishlist proposals eligible for automatic implementation."
    assert_includes context, "### 1. Wish 1"
    assert_includes context, "### 2. Wish 2"
    assert_includes context, "anchor: lib/sample.rb:1"
    assert_includes context, "change: make the next improvement explicit"
    assert_includes context, "evidence: sample.rb is present in the oriented tree"
    assert_includes context, "Treat each supported next_fix proposal as an actual repair target"
  end
end
