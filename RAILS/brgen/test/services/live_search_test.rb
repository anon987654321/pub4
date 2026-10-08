# frozen_string_literal: true

require "test_helper"

class LiveSearchTest < ActiveSupport::TestCase
  test "empty query returns original scope without filtering" do
    scope = Marketplace::Listing.none
    result = Shared::LiveSearch.search(scope, query: "", columns: %w[title])
    assert_equal scope, result.scope
    assert_equal 0, result.result_count
  end

  test "like fallback filters listings by title" do
    user = User.create!(email_address: "seller-#{SecureRandom.hex(4)}@example.com", password: "secret123!")
    category = Marketplace::Category.create!(name: "Bikes", slug: "bikes-#{SecureRandom.hex(4)}")
    listing = Marketplace::Listing.create!(
      user: user,
      category: category,
      title: "Vintage Bicycle Oslo",
      description: "Well maintained",
      price_cents: 12_000,
      status: "active"
    )
    result = Shared::LiveSearch.search(
      Marketplace::Listing.where(id: listing.id),
      query: "Bicycle",
      columns: %w[title description],
      vertical: "marketplace",
      app: "brgen"
    )
    assert_includes result.scope.pluck(:id), listing.id
    assert_operator result.result_count, :>=, 1
  end
end
