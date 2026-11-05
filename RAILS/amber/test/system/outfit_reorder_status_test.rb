# frozen_string_literal: true

require "application_system_test_case"

# Reordering an outfit's garments says whether the order was saved, and a
# failed save puts the garments back in the order the server holds.
class OutfitReorderStatusTest < ApplicationSystemTestCase
  test "a reorder says it was saved, and a failed one says so and reverts" do
    user = create_user("reorder")
    outfit = Outfit.create!(user: user, name: "Autumn")
    %w[Coat Scarf].each_with_index do |title, position|
      item = Item.create!(user: user, title: title, category: "Outerwear")
      OutfitItem.create!(outfit: outfit, item: item, position: position)
    end

    sign_in(user)
    visit outfit_path(outfit)
    locale = page_locale
    before = dom_order

    move_first_down(locale)
    assert_selector "#outfit-order-status", text: I18n.t("outfits.order_saved", locale: locale)
    assert_equal before.reverse, dom_order
    assert_equal before.reverse, stored_order(outfit)

    saved = dom_order
    execute_script("window.fetch = () => Promise.reject(new TypeError('offline'))")
    move_first_down(locale)
    assert_selector "#outfit-order-status", text: I18n.t("outfits.order_failed", locale: locale)
    assert_equal saved, dom_order, "the failed move stayed on the page"
    assert_equal saved, stored_order(outfit)
  end

  private

  def move_first_down(locale)
    label = I18n.t("actions.move_down", locale: locale)
    first_card.find("button[aria-label='#{label}']").click
  end

  def stored_order(outfit)
    OutfitItem.where(outfit: outfit).order(:position).pluck(:item_id).map(&:to_s)
  end

  def grid = find("[data-controller='outfit-sortable']")
  def first_card = grid.first(":scope > [data-id]")
  def dom_order = grid.all(":scope > [data-id]").map { |card| card[:"data-id"] }
end
