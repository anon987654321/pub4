# frozen_string_literal: true

require "test_helper"

# The declutter review printed score keys with String#humanize ("Total
# release score") and raw floats ("0.437"), the dashboard printed the
# joy/use matrix keys humanized ("High joy low use") and challenge dates as
# "— due 2026-11-11", English and ISO in every locale.
class DeclutterScoresI18nTest < ActionDispatch::IntegrationTest
  setup do
    email = "ds-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    @item = Item.strict_loading(false).create!(user: @user, title: "Frakk", category: "outerwear",
                                               lifecycle_state: "active", times_worn: 0, price_cents: 0)
  end

  test "review scores are labelled in nb and read as percentages" do
    get review_declutter_path(@item, locale: "nb")
    assert_response :success
    assert_select "dl.meta dt", text: I18n.t("declutter.score_keys.total_release_score", locale: :nb)
    values = css_select("dl.meta dd").map(&:text)
    assert_empty values.grep(/\A\d+\.\d+\z/), "raw floats: #{values.inspect}"
    assert values.any? { |value| value.end_with?("%") }
  end

  test "the dashboard names quadrants and dates challenges in nb" do
    due = Date.current + 5
    DeclutterChallenge.create!(user: @user, item: @item, due_on: due, note: "x")

    get declutter_index_path(locale: "nb")
    assert_response :success
    assert_includes response.body, I18n.t("declutter.due", date: I18n.l(due, locale: :nb), locale: :nb)
    assert_not_includes response.body, "— due"
    assert_no_match(/High joy|Low joy/, response.body)
  end
end
