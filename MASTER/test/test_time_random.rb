# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/master/time"
require_relative "../lib/master/random"

class TestMasterTimeRandom < Minitest::Test
  def test_time_seam_exposes_wall_and_monotonic_clocks
    assert_kind_of ::Time, Master::Time.now
    assert_kind_of ::Time, Master::Time.utc_now
    assert_kind_of Numeric, Master::Time.monotonic
  end

  def test_random_seam_is_reproducible
    assert_equal Master::Random.rng(42).rand(10), Master::Random.rng(42).rand(10)
  end
end
