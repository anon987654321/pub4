# frozen_string_literal: true

require "test_helper"

class DatingUnmatchTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @me = user_named("un_me")
    @them = user_named("un_them")
    @stranger = user_named("un_stranger")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def user_named(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123",
      username: handle, guest: false, city: @city
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a participant can unmatch and the row leaves the list" do
    match = nil
    ActsAsTenant.with_tenant(@city) do
      match = Dating::Match.create!(initiator: @me, receiver: @them, status: "matched")
    end
    sign_in_as(@me)
    host! "dating.brgen.no"

    delete dating.match_path(match)
    assert_redirected_to dating.matches_path
    assert_equal "unmatched", match.reload.status

    get dating.matches_path
    assert_response :success
    refute_includes response.body, @them.display_name
  end

  test "a stranger cannot unmatch someone else's pair" do
    match = nil
    ActsAsTenant.with_tenant(@city) do
      match = Dating::Match.create!(initiator: @me, receiver: @them, status: "matched")
    end
    sign_in_as(@stranger)
    host! "dating.brgen.no"

    delete dating.match_path(match)
    assert_response :not_found
    assert_equal "matched", match.reload.status
  end
end
