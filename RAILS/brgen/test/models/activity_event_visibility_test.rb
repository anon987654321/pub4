# frozen_string_literal: true
require "test_helper"
class ActivityEventVisibilityTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no"); ActsAsTenant.current_tenant = @city
    @user = User.create!(email_address: "ae-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "ae_#{SecureRandom.hex(3)}", city: @city)
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "public_only keeps private activity off the profile" do
    pub  = ActivityEvent.create!(actor: @user, source_vertical: "social", event_name: "PostCreated",  object_type: "Post", object_id: 1, visibility: "public",  moderation_state: "clean")
    priv = ActivityEvent.create!(actor: @user, source_vertical: "dating", event_name: "DatingLike",    object_type: "User", object_id: 2, visibility: "private", moderation_state: "clean")
    ids = ActivityEvent.visible.public_only.where(actor_id: @user.id).pluck(:id)
    assert_includes ids, pub.id
    assert_not_includes ids, priv.id, "a private dating like must never surface on a profile"
  end
end
