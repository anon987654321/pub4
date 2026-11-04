# frozen_string_literal: true

require "test_helper"

# Item cards and the item page printed category, lifecycle state, mood and
# life phase as stored ("outerwear", "Declutter box" via humanize,
# "past-self"), though the forms choose them from translated labels.
class ItemEnumLabelsTest < ActionDispatch::IntegrationTest
  setup do
    email = "ie-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    @item = Item.strict_loading(false).create!(user: @user, title: "Frakk", category: "Outerwear", times_worn: 0,
                                               price_cents: 0, lifecycle_state: "repair", mood_effect: "calming",
                                               life_phase: "past-self")
  end

  test "the item page names its enums in nb" do
    get item_path(@item, locale: "nb")
    assert_response :success
    assert_select "dd", text: "Yttertøy"
    assert_select ".tag", text: I18n.t("lifecycle_states.repair", locale: :nb).upcase_first
    assert_select ".tag--phase", text: "Tidligere meg"
    assert_includes response.body, "Beroligende"
    assert_no_match(/>past-self<|>Repair</, response.body)
  end

  test "a wardrobe card names its category in nb" do
    get items_path(locale: "nb")
    assert_select "article.item-card span", text: "Yttertøy"
  end
end
