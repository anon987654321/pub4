# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/commerce"

class SharedCommerceTest < Minitest::Test
  def test_canonical_id_is_stable_and_namespaced
    assert_equal(
      "pub4-commerce-v1:brgen:listing:23:991",
      Shared::Commerce.canonical_id(source: "brgen", type: "listing", city_id: 23, record_id: 991)
    )
  end

  def test_query_normalization_is_small_and_deterministic
    assert_equal %w[wool coat black], Shared::Commerce.normalize_query("Wool, coat. BLACK wool")
  end

  def test_scores_are_bounded
    assert_equal 0.0, Shared::Commerce.score(-1)
    assert_equal 1.0, Shared::Commerce.score(2)
  end
end
