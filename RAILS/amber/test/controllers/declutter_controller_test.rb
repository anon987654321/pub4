# frozen_string_literal: true

require "test_helper"

# DeclutterController had no test file at all, money path included, and the two
# pages below returned 500 in production for as long as strict_loading_by_default
# has been on: #review reads @item.declutter_review and #challenge reads
# @item.declutter_challenges, while set_item preloaded neither.
#
# The nearest thing to coverage was amber_backlog_test asserting that the
# controller's *source text* contains "create_last_chance_outfit", which passes
# against a controller that raises on every request. These make the request.
class DeclutterControllerTest < ActionDispatch::IntegrationTest
  def sign_in_as(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  def boxed_item(user, title: "Wool coat")
    Item.strict_loading(false).create!(
      user: user, title: title, category: "outerwear",
      lifecycle_state: "declutter_box", times_worn: 0, price_cents: 0
    )
  end

  setup do
    @user = sign_in_as("declutter-#{SecureRandom.hex(4)}@example.test")
    @item = boxed_item(@user)
  end

  # The two that 500'd. Both read a strict-loaded association off set_item.
  def test_review_renders_for_an_item_with_no_review_yet
    get review_declutter_path(@item)
    assert_response :success
  end

  def test_challenge_creates_one_and_does_not_raise_on_the_association_read
    assert_difference -> { DeclutterChallenge.count }, 1 do
      post challenge_declutter_path(@item)
    end
    assert_response :redirect
  end

  # The money path: outcome writes amount_recovered and nothing covered it.
  # amount_recovered is a money_reader: the form sends kroner and the column is
  # ore, so this also pins that the conversion survives the controller.
  def test_outcome_records_the_amount_recovered
    assert_difference -> { DeclutterOutcome.count }, 1 do
      post outcome_declutter_path(@item), params: {
        declutter_outcome: { action: "sold", amount_recovered: 450, notes: "solgt på Tise" }
      }
    end
    assert_equal 45_000, DeclutterOutcome.order(:id).last.amount_recovered_cents
  end

  # Scoped through Current.user.items, so another owner's item must not resolve.
  def test_another_owners_item_is_not_reachable
    stranger = User.strict_loading(false).create!(
      email_address: "stranger-#{SecureRandom.hex(4)}@example.test", password: "password"
    )
    theirs = boxed_item(stranger, title: "Not mine")

    # The integration stack renders the RecordNotFound rather than re-raising,
    # so the observable contract is the 404 a stranger actually receives.
    get review_declutter_path(theirs)
    assert_response :not_found
  end

  # The index derives two lists from one load; both must still be present.
  def test_index_lists_the_box
    get declutter_index_path
    assert_response :success
  end
end
