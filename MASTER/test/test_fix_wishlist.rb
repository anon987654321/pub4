# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/ai/orientation"
require_relative "../lib/fix/wishlist"
require "tmpdir"
require "fileutils"
require "json"

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
    (1..3).map do |i|
      "- id: wish_#{i}\n  title: Wish #{i}\n  rationale: improve something measurable\n  anchor: lib/sample.rb:1\n  change: make the next improvement explicit\n  effort: cheap\n  reversibility: reversible\n  implementation: next_fix\n  evidence: sample.rb is present in the oriented tree\n  proof:\n    - ruby syntax"
    end.join("\n")
  end

  def test_call_writes_a_bounded_evidence_linked_report
    agent = RecordingAgent.new(reply)
    result = Master::Fix::Wishlist.new(root: @root, agent:, event_bus: @bus).call(state: "done", target: @root, run_id: "r1")

    assert_equal "wishlist: drafted 3, queued 3 → .master/fix_wishlist.json", result
    ledger = JSON.parse(File.read(File.join(@root, ".master", "fix_wishlist.json")))
    assert_equal 3, ledger.fetch("proposals").size
    assert_equal %w[queued queued queued], ledger.fetch("proposals").map { |row| row.fetch("status") }
    assert_includes ledger.fetch("proposals").first.fetch("proof"), "ruby syntax"
    refute File.exist?(File.join(@root, "runtime", "wishlist.md"))
    assert_includes @bus.events.map { |e| e[:event] }, "wishlist:done"
  end

  def test_invalid_file_anchors_are_dropped_without_losing_the_valid_queue
    bad = reply.dup
    bad = bad.sub("anchor: lib/sample.rb:1", "anchor: lib/missing.rb:99")
    agent = RecordingAgent.new(bad)
    result = Master::Fix::Wishlist.new(root: @root, agent:).call(state: "done", target: @root, run_id: "r2")

    assert_equal "wishlist: drafted 2, queued 2 → .master/fix_wishlist.json", result
  end

  def test_pending_context_exposes_durable_queue_without_markdown
    agent = RecordingAgent.new(reply)
    Master::Fix::Wishlist.new(root: @root, agent:).call(state: "done", target: @root, run_id: "r3")

    context = Master::Fix::Wishlist.pending_context(@root, target: @root, limit: 2)
    assert_includes context, "Pending automatic convergence proposals from the durable /fix ledger."
    assert_includes context, "proposal: wish_1-"
    assert_includes context, "anchor: lib/sample.rb:1"
    assert_includes context, "change: make the next improvement explicit"
    assert_includes context, "proof: ruby syntax"
    refute_includes context, "### 1."
  end

  def test_operator_and_research_items_are_not_automatic
    response = [
      "- id: operator\n  title: Device proof\n  rationale: needs a real phone\n  anchor: run:device\n  change: verify the microphone\n  effort: deep\n  reversibility: operator\n  implementation: operator\n  evidence: device proof is external",
      "- id: research\n  title: Research seam\n  rationale: needs investigation\n  anchor: lib/sample.rb:1\n  change: investigate the seam\n  effort: medium\n  reversibility: guarded\n  implementation: research\n  evidence: current evidence is incomplete",
      "- id: automatic\n  title: Automatic repair\n  rationale: bounded source change\n  anchor: lib/sample.rb:1\n  change: make the bounded change\n  effort: cheap\n  reversibility: reversible\n  implementation: next_fix\n  evidence: sample.rb is present",
    ].join("\n")
    agent = RecordingAgent.new(response)
    Master::Fix::Wishlist.new(root: @root, agent:).call(state: "done", target: @root, run_id: "r4")

    pending = Master::Fix::Wishlist.new(root: @root, agent:).claimable(target: @root, limit: 10, run_id: "r4")
    assert_equal ["automatic"], pending.map { |row| row.fetch("id") }
  end

  def test_changed_anchor_is_stale_and_not_claimed
    agent = RecordingAgent.new(reply)
    Master::Fix::Wishlist.new(root: @root, agent:).call(state: "done", target: @root, run_id: "r5")
    File.write(File.join(@root, "lib", "sample.rb"), "module Changed\nend\n")

    pending = Master::Fix::Wishlist.new(root: @root, agent:).claimable(target: @root, limit: 10, run_id: "r6")
    assert_empty pending
    ledger = JSON.parse(File.read(File.join(@root, ".master", "fix_wishlist.json")))
    assert ledger.fetch("proposals").all? { |row| row.fetch("status") == "stale" }
  end
end
