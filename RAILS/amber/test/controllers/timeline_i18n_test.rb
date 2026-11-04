# frozen_string_literal: true

require "test_helper"

# The style timeline was titled "Style evolution" in every locale, joined
# item and outfit with a hardcoded "in", and printed wear dates as ISO.
class TimelineI18nTest < ActionDispatch::IntegrationTest
  test "the wear history reads in nb" do
    email = "tl-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    shirt = user.items.create!(title: "Linskjorte", category: "Tops")
    outfit = Outfit.strict_loading(false).create!(user:, name: "Fredag")
    outfit.items << shirt
    worn = Date.new(2026, 10, 2)
    shirt.wear!(worn_on: worn, outfit:)

    get timeline_wardrobe_items_path(locale: "nb")
    assert_response :success
    assert_select "title", text: /\A#{Regexp.escape(I18n.t("pages.timeline", locale: :nb))}/
    assert_select "ol.style-timeline time[datetime='2026-10-02']", text: I18n.l(worn, locale: :nb)
    assert_includes response.body, I18n.t("wardrobe.worn_in", outfit: "Fredag", locale: :nb)
  end
end
