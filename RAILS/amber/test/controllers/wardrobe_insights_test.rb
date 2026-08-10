# frozen_string_literal: true

require "test_helper"

class WardrobeInsightsTest < ActionDispatch::IntegrationTest
  def sign_in_as(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  test "analytics draws a figure for every clause of the original goal" do
    user = sign_in_as("insights-figures@example.com")
    user.items.create!(title: "Gala dress", category: "Dresses", price_cents: 90_000, times_worn: 2, last_worn_on: 300.days.ago.to_date)
    user.items.create!(title: "Daily tee", category: "Tops", price_cents: 2_000, times_worn: 40, last_worn_on: Date.current)

    get analytics_wardrobe_items_path

    assert_response :success
    %w[viz-category-mix-title viz-wear-distribution-title viz-cost-per-wear-title viz-idle-title].each do |id|
      assert_select "##{id}", count: 1
    end
    assert_select ".viz-fill", minimum: 2
  end

  test "analytics surfaces cost-per-wear, which the page used to compute and drop" do
    user = sign_in_as("insights-cpw@example.com")
    user.items.create!(title: "Gala dress", category: "Dresses", price_cents: 90_000, times_worn: 2)

    get analytics_wardrobe_items_path

    assert_response :success
    # The chip's wording is localised (the suite runs under nb), so assert on
    # the figure itself: $900 over two wears is $450 each time it goes on.
    assert_select ".chip", text: /450/
    assert_select "#viz-cost-per-wear-title"
    assert_select ".viz-row", text: /Gala dress/
  end

  test "an empty wardrobe renders the analytics page without dividing by zero" do
    sign_in_as("insights-empty@example.com")

    get analytics_wardrobe_items_path

    assert_response :success
    assert_select ".viz-plot .viz-column", 6
  end

  test "closet organization is reachable and groups tips by register" do
    user = sign_in_as("insights-organize@example.com")
    user.items.create!(title: "Torn coat", category: "Outerwear", lifecycle_state: "repair", material: "wool")
    user.items.create!(title: "Silk blouse", category: "Tops", material: "silk", times_worn: 9)
    user.items.create!(title: "Loafers", category: "Shoes", material: "leather", color: "tan")

    get organize_wardrobe_items_path

    assert_response :success
    assert_select "#register-care"
    assert_select "#register-storage"
    assert_select ".organize-tip .organize-principle", minimum: 3
  end

  test "closet organization says so plainly when there is nothing to correct" do
    sign_in_as("insights-organize-empty@example.com")

    get organize_wardrobe_items_path

    assert_response :success
    assert_select ".organize-tip", 0
  end

  test "both insight pages need a session" do
    get analytics_wardrobe_items_path
    assert_redirected_to new_session_path

    get organize_wardrobe_items_path
    assert_redirected_to new_session_path
  end
end
