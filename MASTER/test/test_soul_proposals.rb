# frozen_string_literal: true

require_relative "test_helper"

class TestSoulProposals < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
      @subs = {}
    end

    def subscribe(pattern, &handler) = (@subs[pattern] ||= []) << handler

    def publish(event, payload = {})
      @events << { event:, payload: }
      (@subs[event] || []).each { |h| h.call(payload) }
    end
  end

  def setup
    @root = Dir.mktmpdir("soul_proposals_test")
    @bus  = FakeBus.new
    @sp   = Master::Loop::SoulProposals.new(event_bus: @bus, root: @root).attach
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def proposal_path
    File.join(@root, Master::Loop::SoulProposals::PROPOSALS_PATH)
  end

  def fire(rule: "BARE_RESCUE", sample: [{ rule: "BARE_RESCUE", file: "lib/foo.rb", line: 12 }])
    @bus.publish("fix_loop:soul_proposal", rule:, sample:)
  end

  def test_appends_proposal_file_on_event
    fire
    assert File.exist?(proposal_path), "proposals file must be created"
    content = File.read(proposal_path)
    assert_includes content, "BARE_RESCUE"
    assert_includes content, "lib/foo.rb"
    assert_includes content, "Delta: + recurring `BARE_RESCUE` finding(s)"
  end

  def test_publishes_soul_proposal_ready
    fire
    ready = @bus.events.select { |e| e[:event] == "soul:proposal_ready" }
    assert_equal 1, ready.size
    assert_equal "BARE_RESCUE", ready.first[:payload][:rule]
    assert_equal Master::Loop::SoulProposals::PROPOSALS_PATH, ready.first[:payload][:path]
  end

  def test_multiple_proposals_append_not_overwrite
    fire(rule: "BARE_RESCUE")
    fire(rule: "LONG_METHOD", sample: [{ rule: "LONG_METHOD", file: "lib/bar.rb", line: 5 }])
    content = File.read(proposal_path)
    assert_includes content, "BARE_RESCUE"
    assert_includes content, "LONG_METHOD"
  end

  def test_ignores_event_with_no_rule
    @bus.publish("fix_loop:soul_proposal", sample: [])
    refute File.exist?(proposal_path), "must not write when rule is absent"
  end

  def test_safe_without_bus
    sp = Master::Loop::SoulProposals.new(event_bus: nil, root: @root).attach
    assert_instance_of Master::Loop::SoulProposals, sp
  end
end
