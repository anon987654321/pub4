# frozen_string_literal: true

require "test_helper"

# The "message me" link is the whole on-ramp for somebody who has no account
# here, so the parts that must not go wrong are: it resolves to the person who
# issued it, it cannot be edited into anyone else's, and it stops working when it
# should.
class MessageInviteTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @host = create_user("host")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(handle, **attrs)
    User.create!(email_address: "#{handle}-#{SecureRandom.hex(4)}@brgen.no",
                 password: "password123", password_confirmation: "password123",
                 username: "#{handle}_#{SecureRandom.hex(3)}", city: @city, **attrs)
  end

  test "a token resolves back to the person who issued it" do
    found = User.find_signed(@host.message_invite_token, purpose: InvitesController::PURPOSE)

    assert_equal @host.id, found&.id
  end

  # The purpose is what stops a token minted for one thing being spent on
  # another; without it any signed_id in the app would open a conversation.
  test "a token minted for something else does not open a conversation" do
    other_purpose = @host.signed_id(purpose: :password_reset)

    assert_nil User.find_signed(other_purpose, purpose: InvitesController::PURPOSE)
  end

  test "a tampered token resolves to nobody" do
    tampered = "#{@host.message_invite_token}x"

    assert_nil User.find_signed(tampered, purpose: InvitesController::PURPOSE)
  end

  test "a token stops working once it has expired" do
    token = @host.message_invite_token

    travel InvitesController::TTL + 1.day do
      assert_nil User.find_signed(token, purpose: InvitesController::PURPOSE)
    end
  end
end
