# frozen_string_literal: true

require "test_helper"

# With no outfits the planner still offered an empty select and a live
# submit that could only fail, and said nothing about why.
class PlannerNoOutfitsTest < ActionDispatch::IntegrationTest
  setup do
    email = "pn-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
  end

  test "an outfit-less planner explains itself and disables the submit" do
    get planned_outfits_path
    assert_response :success
    assert_select ".empty-state a[href=?]", new_outfit_path
    assert_select "input[type=submit][disabled]", 1
  end

  test "a planner with an outfit keeps the submit live" do
    Outfit.strict_loading(false).create!(user: @user, name: "Fredag")
    get planned_outfits_path
    assert_select "input[type=submit][disabled]", 0
    assert_select ".empty-state a[href=?]", new_outfit_path, 0
  end
end
