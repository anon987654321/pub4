# frozen_string_literal: true

require_relative "test_helper"
require "master"

# frozen_string_literal: true
class NoSecretNoteTest < Minitest::Test
  def test_blocks_secrets_in_note_text
    data_dir = File.expand_path("../data", __dir__)
    constitution = Master::Core::Constitution.load(data_dir:)
    memory = Master::Core::Memory.new
    effect = Master::Core::Effect.note(:debug, "token sk-#{'A' * 24}")

    verdict = constitution.admit(effect, memory)

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :no_secret, verdict.by
  end
end

# frozen_string_literal: true
class TestCapabilityMap < Minitest::Test
  def setup
    @map = Master::CLI::Routing::CapabilityMap.new
  end

  def test_recording_outcomes
    @map.record_outcome("gemma", :coding, true, { latency: 1.2 })
    @map.record_outcome("gemma", :coding, false, { latency: 1.5 })

    assert_equal 0.5, @map.success_rate("gemma", :coding)
    assert_equal 1.35, @map.scores["gemma"]["coding"][:metrics][:latency]
  end

  def test_best_model_selection
    3.times { @map.record_outcome("gemma", :coding, true) }
    3.times { @map.record_outcome("qwen", :coding, false) }

    assert_equal "gemma", @map.best_model_for(:coding)
  end

  def test_unmeasured_and_sparse_models_stay_near_neutral
    assert_equal 0.5, @map.score_for("new-model", :coding)

    2.times { @map.record_outcome("new-model", :coding, false) }
    assert_operator @map.score_for("new-model", :coding), :<, 0.5
    assert_operator @map.score_for("new-model", :coding), :>, 0.0
  end

  # The store is written through the writer the caller hands in, and a map
  # built on the same path reads it back.
  def test_outcomes_persist_through_the_injected_writer
    Dir.mktmpdir do |dir|
      path = File.join(dir, "caps.json")
      written = []
      write = lambda do |target, content|
        written << target
        File.write(target, content)
      end
      Master::CLI::Routing::CapabilityMap.new(path:, write:).record_outcome("gemma", :coding, true)

      assert_equal [path], written
      assert_equal 1.0, Master::CLI::Routing::CapabilityMap.new(path:).success_rate("gemma", "coding")
    end
  end
end

# frozen_string_literal: true
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

# frozen_string_literal: true

require "minitest/autorun"
class VerbClosureTest < Minitest::Test
  CLOSED = Master::Core::VERBS.freeze

  def test_closed_verb_set_matches_proposal
    expected = %i[read write exec git ask note critique done]
    assert_equal expected.sort, CLOSED.sort
  end

  def test_model_system_prompt_lists_only_closed_verbs
    prompt = Master::Core::Model::SYSTEM
    %w[read write exec git ask note critique done].each do |verb|
      assert_match(/\b#{verb}\b/, prompt, "prompt must document #{verb}")
    end
  end
end
