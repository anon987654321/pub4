# frozen_string_literal: true

require "test_helper"
class BlockingTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @me   = User.create!(email_address: "me-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "me_#{SecureRandom.hex(3)}", city: @city)
    @them = User.create!(email_address: "them-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "them_#{SecureRandom.hex(3)}", city: @city)
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "blocking hides the blocked user's posts from the feed" do
    theirs = Post.create!(user: @them, title: "hi from them", content: "x")
    assert_includes Brgen::HomeFeed.scope(authenticated: true, user: @me).to_a, theirs
    @me.block!(@them)
    assert @me.blocking?(@them)
    assert_not_includes Brgen::HomeFeed.scope(authenticated: true, user: @me.reload).to_a, theirs
    @me.unblock!(@them)
    assert_includes Brgen::HomeFeed.scope(authenticated: true, user: @me.reload).to_a, theirs
  end

  test "cannot block yourself" do
    assert_nil @me.block!(@me)
    assert_not @me.blocking?(@me)
  end
end
