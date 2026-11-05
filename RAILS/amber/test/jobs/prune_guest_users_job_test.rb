# frozen_string_literal: true

require "test_helper"

# amber schedules the shared guest prune too, but has no messenger and so no
# ConversationParticipant. The job raised NameError on every run in production.
class PruneGuestUsersJobTest < ActiveSupport::TestCase
  def build_guest(created_at:)
    user = User.new(email_address: "guest_#{SecureRandom.hex(6)}@guest.local", guest: true)
    user.password_digest = BCrypt::Password.create("x", cost: BCrypt::Engine::MIN_COST)
    user.save!
    user.update_column(:created_at, created_at)
    user
  end

  test "prunes a stale guest in an app without conversations" do
    stale = build_guest(created_at: 30.days.ago)
    recent = build_guest(created_at: 1.hour.ago)

    Shared::PruneGuestUsersJob.perform_now

    refute User.exists?(stale.id), "stale sessionless guest should be pruned"
    assert User.exists?(recent.id), "a guest younger than the window is still in use"
  end
end
