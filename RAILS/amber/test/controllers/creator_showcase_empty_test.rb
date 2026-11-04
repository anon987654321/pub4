# frozen_string_literal: true

require "test_helper"

# An empty showcase offered every visitor "edit showcase", a link to
# edit_my_creator_profile_path, which is the visitor's own profile.
class CreatorShowcaseEmptyTest < ActionDispatch::IntegrationTest
  setup do
    email = "cr-#{SecureRandom.hex(4)}@example.test"
    @owner = User.strict_loading(false).create!(email_address: email, password: "password")
    @profile = @owner.create_creator_profile!(handle: "cr#{SecureRandom.hex(3)}", display_name: "Creator", public: true)
  end

  test "a visitor sees the empty showcase without the owner's edit action" do
    get creator_profile_path(@profile.handle)
    assert_response :success
    assert_select ".empty-state", text: /#{I18n.t("empty.no_showcase")}/
    assert_select ".empty-state a[href=?]", edit_my_creator_profile_path, 0
  end

  test "the owner is offered the edit action" do
    post session_path, params: { email_address: @owner.email_address, password: "password" }
    get creator_profile_path(@profile.handle)
    assert_select ".empty-state a[href=?]", edit_my_creator_profile_path, 1
  end
end
