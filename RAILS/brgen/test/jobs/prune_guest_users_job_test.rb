# frozen_string_literal: true

require "test_helper"

# The job existed, was correct, and was enqueued by nothing — so every cookieless
# request's guest row lived forever (102,778 of them on 2026-08-01, 99.3% of the
# users table). These tests pin the three things that have to hold together: the
# job removes the right rows, the schedule exists, and the index its scan needs
# is in the schema.
class PruneGuestUsersJobTest < ActiveSupport::TestCase
  def build_guest(created_at:)
    user = User.new(email_address: "guest_#{SecureRandom.hex(6)}@guest.local", guest: true)
    user.password_digest = BCrypt::Password.create("x", cost: BCrypt::Engine::MIN_COST)
    user.save!
    user.update_column(:created_at, created_at)
    user
  end

  test "destroys stale sessionless guests and keeps everything else" do
    stale = build_guest(created_at: 30.days.ago)
    recent = build_guest(created_at: 1.hour.ago)
    signed_in = build_guest(created_at: 30.days.ago)
    signed_in.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    real = User.create!(email_address: "real_#{SecureRandom.hex(6)}@example.com", password: "secret123",
                        guest: false)
    real.update_column(:created_at, 30.days.ago)

    Shared::PruneGuestUsersJob.perform_now

    refute User.exists?(stale.id), "stale sessionless guest should be pruned"
    assert User.exists?(recent.id), "a guest younger than the window is still in use"
    assert User.exists?(signed_in.id), "a guest with a session is an active visitor"
    assert User.exists?(real.id), "real accounts are never guest rows"
  end

  # in_batches(of: 500, &:destroy_all) over a relation carrying a LEFT OUTER JOIN
  # removed 3,832 of 143,339 eligible rows on production and reported success.
  # More rows than one batch is the condition that exposed it, so the test uses
  # more than one batch.
  test "removes every eligible guest, not just the first batch" do
    over_one_batch = Shared::PruneGuestUsersJob::BATCH + 20
    ids = Array.new(over_one_batch) { build_guest(created_at: 30.days.ago).id }

    Shared::PruneGuestUsersJob.perform_now

    assert_equal 0, User.where(id: ids).count,
                 "left #{User.where(id: ids).count} of #{over_one_batch} behind — batching stopped early again"
  end

  # A guest who has been in a conversation owns message_receipts, which carry an
  # FK to users. Without has_many on User the destroy raises FOREIGN KEY
  # constraint failed from SQLite, and the job dies on the first batch containing
  # one. Guests owned 194,295 receipts on production when this was found.
  test "destroys a guest that owns message receipts" do
    guest = build_guest(created_at: 30.days.ago)
    author = User.create!(email_address: "author_#{SecureRandom.hex(4)}@example.com",
                          password: "secret123", guest: false)
    conversation = Conversation.create!(conversation_type: "direct")
    conversation.conversation_participants.create!(user: author)
    conversation.conversation_participants.create!(user: guest)
message = conversation.messages.create!(sender: author, content: "hei", message_type: "text")
# deliver_receipts already made the guest's receipt on create. This used to
# add a second one, which only worked because message_receipts had no unique
# index — 20260827090000 added it, so the duplicate is now the error it
# always was. Assert the receipt exists rather than making another.
assert message.message_receipts.exists?(user: guest), "the callback should have delivered one"

    Shared::PruneGuestUsersJob.perform_now

    refute User.exists?(guest.id), "a guest with a message receipt must still be prunable"
  end

  test "is scheduled in production" do
    schedule = YAML.safe_load_file(Rails.root.join("config/recurring.yml")).fetch("production")
    entry = schedule.fetch("prune_guest_users")

    assert_equal "Shared::PruneGuestUsersJob", entry.fetch("class")
    assert_match(/every day/, entry.fetch("schedule"))
  end

  # A daily full scan of the largest table on a 1-vCPU box is the reason the
  # index and the schedule landed in the same change.
  test "the scan the job performs is indexed" do
    assert_includes File.read(Rails.root.join("db/schema.rb")),
                    "index_users_on_guest_and_created_at"
  end
end
