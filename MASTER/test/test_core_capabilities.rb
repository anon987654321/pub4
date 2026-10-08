# frozen_string_literal: true

require "minitest/autorun"
require "master"

class CoreCapabilitiesTest < Minitest::Test
  E = Master::Core::Effect

  def test_effect_capability_is_derived_from_verb
    assert_equal :read, E.read("x").capability
    assert_equal :write, E.write("x", "body").capability
    assert_equal :execute, E.exec(%w[echo hi]).capability
    assert_equal :read, E.git(:diff).capability
    assert_equal :write, E.git(:stage, paths: ["x"]).capability
    assert_equal :stdio, E.done("done").capability
  end

  def test_effect_cannot_forge_a_capability
    assert_raises(ArgumentError) do
      E.new(verb: :write, args: { path: "x", content: "x" }, capability: :read)
    end
  end

  def test_capabilities_only_reduce
    capabilities = Master::Core::Capabilities.for(:fix)

    assert capabilities.allow?(:write)
    capabilities.drop(:write)

    refute capabilities.allow?(:write)
    assert_raises(SecurityError) { capabilities.require!(:write) }
    assert_raises(SecurityError) { capabilities.acquire(:write) }
  end

  def test_locked_capabilities_cannot_change
    capabilities = Master::Core::Capabilities.for(:fix).lock!

    assert capabilities.locked?
    assert_raises(SecurityError) { capabilities.drop(:execute) }
  end

  def test_read_only_profile_has_no_write_or_execute
    capabilities = Master::Core::Capabilities.read_only

    assert capabilities.allow?(:read)
    refute capabilities.allow?(:write)
    refute capabilities.allow?(:execute)
  end

  def test_constitution_blocks_effects_missing_current_capability
    capabilities = Master::Core::Capabilities.read_only
    constitution = Master::Core::Constitution.new(laws: [], capabilities:)
    memory = Master::Core::Memory.new

    verdict = constitution.admit(E.write("x", "x"), memory)

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :capability, verdict.by
  end

  def test_world_blocks_a_direct_bypass
    capabilities = Master::Core::Capabilities.read_only
    Dir.mktmpdir do |root|
      world = Master::Core::World.new(root:, capabilities:)
      assert_raises(SecurityError) { world.perform(E.write("x", "x")) }
    end
  end
end
