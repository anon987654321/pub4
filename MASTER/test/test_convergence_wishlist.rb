# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/convergence/wishlist"

class TestConvergenceWishlist < Minitest::Test
  def test_registry_has_unique_ids_and_honest_states
    items = Master::Convergence::Wishlist.items(root: Master::ROOT)
    assert_operator items.size, :>=, 20
    assert_equal items.map { |item| item[:id] }.uniq.size, items.size
    items.each { |item| assert_includes Master::Convergence::STATES.map(&:to_s), item[:state] }
  end

  def test_render_can_filter_one_workstream
    result = Master::Convergence::Wishlist.render("snapshot", root: Master::ROOT)
    assert_includes result, "snapshot_exchange"
    assert_includes result, "share-size"
  end
end
