# frozen_string_literal: true

require "test_helper"

# The declutter review printed its move targets and decision options with
# String#humanize ("Wear this week", "Sentimental archive") and prefilled
# the challenge note in English, so an nb reader got English controls; the
# move nav was also the page's one unnamed nav.
class DeclutterReviewI18nTest < ActionDispatch::IntegrationTest
  setup do
    email = "dr-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    @item = Item.strict_loading(false).create!(user:, title: "Frakk", category: "outerwear",
                                               lifecycle_state: "declutter_box", times_worn: 0, price_cents: 0)
  end

  test "move buttons, decision options and the challenge note are in nb" do
    get review_declutter_path(@item, locale: "nb")
    assert_response :success
    assert_select "nav[aria-label=?] button", I18n.t("declutter.move_item", locale: :nb),
                  text: I18n.t("declutter.targets.wear_this_week", locale: :nb)
    sell = I18n.t("declutter.targets.sell", locale: :nb)
    assert_select "select[name='declutter_review[decision]'] option[value=sell]", text: sell
    assert_select "input[name=note][value=?]", I18n.t("flash.wear_once_note", locale: :nb)
    assert_not_includes response.body, "Wear this week"
  end
end
