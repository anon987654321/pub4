# frozen_string_literal: true

require "test_helper"

class DatingRewindTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @me = user_named("rw_me")
    @them = user_named("rw_them")
    @other = user_named("rw_other")
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

  test "rewind undoes the last pass and leaves earlier ones" do
    ActsAsTenant.with_tenant(@city) do
      Dating::Dislike.create!(disliker: @me, dislikee: @other, created_at: 1.minute.ago)
      Dating::Dislike.create!(disliker: @me, dislikee: @them)
    end
    sign_in_as(@me)
    host! "dating.brgen.no"

    assert_difference -> { Dating::Dislike.where(disliker: @me).count }, -1 do
      post dating.rewind_path
    end
    assert_redirected_to dating.root_path
    refute Dating::Dislike.exists?(disliker: @me, dislikee: @them)
    assert Dating::Dislike.exists?(disliker: @me, dislikee: @other)
  end

  test "rewind with nothing to undo does not delete a like" do
    ActsAsTenant.with_tenant(@city) do
      Dating::Like.create!(liker: @me, likee: @them)
    end
    sign_in_as(@me)
    host! "dating.brgen.no"

    assert_no_difference -> { Dating::Like.count } do
      assert_no_difference -> { Dating::Dislike.count } do
        post dating.rewind_path
      end
    end
    assert_redirected_to dating.root_path
  end
end
