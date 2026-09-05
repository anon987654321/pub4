# frozen_string_literal: true

require_relative "test_helper"

# Review::Consensus fans a candidate fix out to three models and ships only on a
# quorum. Which three is a routing decision, and it lived in two places: the
# class held the ids under a comment asking the next reader to keep them in step
# with models.yml. A list kept in step by hand is a list where the next model
# swapped in one place leaves the other voting with a model nothing routes to.
class TestConsensus < Minitest::Test
  def pool = Master.three_mirror_pool

  def test_the_pool_comes_from_models_yml
    declared = Master.load_yaml(Master.data_path("models.yml"))
                     .fetch("three_mirror_redundancy").fetch("pool")

    assert_equal declared, pool
    refute_empty pool, "a quorum over an empty pool approves nothing and says nothing"
  end

  def test_consensus_takes_its_default_from_that_one_source
    assert_equal pool, Master::Review::Consensus.default_models
  end

  # The injection point stays: a caller naming its own models is not overridden
  # by the default, which is what makes the default safe to read from a file.
  def test_an_explicit_pool_wins
    consensus = Master::Review::Consensus.new(agent: nil, models: ["only/one"])

    assert_equal ["only/one"], consensus.instance_variable_get(:@models)
  end

  def test_quorum_is_two_of_three
    assert_equal 2, Master::Review::Consensus::QUORUM
    assert_operator pool.size, :>=, Master::Review::Consensus::QUORUM,
                    "a quorum larger than the pool can never be met"
  end
end
