# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestDeviceAgent < Minitest::Test
  class FakeCognition
    attr_reader :ticks

    def initialize
      @ticks = 0
    end

    def tick!
      @ticks += 1
    end
  end

  class FakeStanding
    attr_reader :owners

    def initialize
      @owners = []
    end

    def run_due!(owner:)
      @owners << owner
      []
    end
  end

  def test_status_is_unpaired_before_local_owner_claim
    Dir.mktmpdir("device-agent") do |root|
      status = Master::Device::Agent.status(root:)
      refute status[:paired]
      assert_equal "", status[:owner_subject]
    end
  end

  def test_tick_persists_runtime_state_without_running_personal_orders
    Dir.mktmpdir("device-agent") do |root|
      cognition = FakeCognition.new
      standing = FakeStanding.new
      agent = Master::Device::Agent.new(root:, bus: nil, cognition:, standing:)
      agent.tick!

      assert_equal 1, cognition.ticks
      assert_empty standing.owners
      status = Master::Device::Agent.status(root:)
      refute_nil status[:last_tick_at]
      refute status[:paired]
    end
  end

  def test_tick_scopes_standing_orders_to_persisted_owner
    Dir.mktmpdir("device-agent") do |root|
      Master::Device::Agent.send(:save_state, root, "owner_subject" => "owner123", "owner_label" => "owner")
      standing = FakeStanding.new
      agent = Master::Device::Agent.new(root:, bus: nil, cognition: FakeCognition.new, standing:)
      agent.tick!

      assert_equal ["owner123"], standing.owners
    end
  end
end
