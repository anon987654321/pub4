# frozen_string_literal: true

require "test_helper"

# The AI analysis card, occasion map, style-profile quiz and declutter review
# printed hardcoded English: "Sparks joy", "← Dashboard", English optgroup
# labels and option text, "← Declutter dashboard".
class AiPagesI18nTest < ActionDispatch::IntegrationTest
  setup do
    email = "ai18n-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
  end

  test "the style quiz labels its options in nb and keeps the values WardrobeAi reads" do
    get ai_style_profile_path(locale: "nb")
    assert_response :success
    assert_select "optgroup", 0
    assert_select "select#answers_lines option[value='minimal clean lines']",
                  text: I18n.t("ai.style_options.lines.minimal_clean_lines", locale: :nb)
  end

  test "the back links are translated" do
    get ai_occasions_path(locale: "nb")
    assert_select "a[href=?]", root_path, text: I18n.t("ai.dashboard_back", locale: :nb)

    item = Item.strict_loading(false).create!(user: @user, title: "Frakk", category: "outerwear",
                                              lifecycle_state: "declutter_box", times_worn: 0, price_cents: 0)
    get review_declutter_path(item, locale: "nb")
    assert_select "a[href=?]", declutter_index_path, text: I18n.t("declutter.back_to_dashboard", locale: :nb)
  end

  test "the analysis card names joy in the reader's language" do
    html = I18n.with_locale(:nb) do
      ApplicationController.render(partial: "ai/analysis", locals: { result: { "sparks_joy" => false }, item: nil })
    end
    assert_includes html, I18n.t("ai.no_spark_joy", locale: :nb)
    assert_not_includes html, "Does not spark joy"
  end
end
