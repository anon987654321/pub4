# frozen_string_literal: true

require_relative "test_helper"

class TestTripleMemory < Minitest::Test
  def setup
    @memory = Master::Core::Memory.new
  end

  def test_semantic_learning
    @memory.semantic.learn("rails_version", "7.1")
    assert_equal "7.1", @memory.semantic.query("rails_version")
  end

  def test_procedural_recipe
    steps = ["read file", "edit line", "run test"]
    @memory.procedural.register_recipe("simple_fix", steps)
    assert_equal steps, @memory.procedural.find_recipe("simple_fix")
  end

  def test_episodic_linking
    episode = Struct.new(:events).new(["turn 1", "turn 2"])
    @memory.link_episode(episode)
    assert_equal ["turn 1", "turn 2"], @memory.episodic.transcript
  end
end
