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

  def test_successful_delivery_requires_and_records_a_deterministic_proof
    agent = RecordingAgent.new(reply)
    wishlist = Master::Fix::Wishlist.new(root: @root, agent:)
    wishlist.call(state: "done", target: @root, run_id: "r6")

    proposals = wishlist.claimable(target: @root, limit: 1, run_id: "r7")
    claimed = wishlist.claim!(proposals, run_id: "r7")
    wishlist.mark_attempt(
      proposal_id: claimed.first.fetch("uid"),
      fixed: 1,
      status: :continue,
      message: "changed",
      run_id: "r7",
    )
    assert_equal 1, wishlist.mark_delivered(proposal_ids: [claimed.first.fetch("uid")], run_id: "r7").size

    verified = wishlist.mark_verified(proposal_ids: [claimed.first.fetch("uid")], run_id: "r8")
    assert_equal "verified", verified.first.fetch("status")
    assert_equal "proven", verified.first.fetch("proof_state")
    assert_includes verified.first.fetch("proof_checks"), "ruby syntax: passed"
  end

  def test_unsupported_proof_never_becomes_verified
    response = reply.sub("ruby syntax", "human listening test")
    wishlist = Master::Fix::Wishlist.new(root: @root, agent: RecordingAgent.new(response))
    wishlist.call(state: "done", target: @root, run_id: "r9")

    proposal = wishlist.claimable(target: @root, limit: 1, run_id: "r10").first
    wishlist.claim!([proposal], run_id: "r10")
    wishlist.mark_attempt(
      proposal_id: proposal.fetch("uid"),
      fixed: 1,
      status: :continue,
      message: "changed",
      run_id: "r10",
    )
    wishlist.mark_delivered(proposal_ids: [proposal.fetch("uid")], run_id: "r10")

    row = wishlist.mark_verified(proposal_ids: [proposal.fetch("uid")], run_id: "r11").first
    assert_equal "applied", row.fetch("status")
    assert_equal "open", row.fetch("proof_state")
    assert_includes row.fetch("verification_reason"), "external validation"
  end

  def test_failed_proof_blocks_instead_of_claiming_success
    response = reply.sub("anchor: lib/sample.rb:1", "anchor: lib/sample.yml:1")
    File.write(File.join(@root, "lib", "sample.yml"), "sample: true\n")
    wishlist = Master::Fix::Wishlist.new(root: @root, agent: RecordingAgent.new(response))
    wishlist.call(state: "done", target: @root, run_id: "r12")

    proposal = wishlist.claimable(target: @root, limit: 1, run_id: "r13").first
    wishlist.claim!([proposal], run_id: "r13")
    wishlist.mark_attempt(
      proposal_id: proposal.fetch("uid"),
      fixed: 1,
      status: :continue,
      message: "changed",
      run_id: "r13",
    )
    wishlist.mark_delivered(proposal_ids: [proposal.fetch("uid")], run_id: "r13")

    row = wishlist.mark_verified(proposal_ids: [proposal.fetch("uid")], run_id: "r14").first
    assert_equal "blocked", row.fetch("status")
    assert_equal "failed", row.fetch("proof_state")
    assert_includes row.fetch("blocked_reason"), "proof failed"
  end

  def test_pending_titles_reads_only_claimable_next_fix_work
    Master::Fix::Wishlist.new(root: @root, agent: RecordingAgent.new(reply)).call(state: "done", target: @root, run_id: "r15")

    assert_equal ["Wish 1", "Wish 2"], Master::Fix::Wishlist.pending_titles(@root, target: @root, limit: 2)
  end

end
