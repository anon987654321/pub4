# frozen_string_literal: true

require "test_helper"

class AccountMergerTest < ActiveSupport::TestCase
  test "a guest and destination pair cannot have duplicate merge audit rows" do
    suffix = SecureRandom.hex(6)
    guest = User.create!(email_address: "guest-#{suffix}@guest.local", password: SecureRandom.hex(24), guest: true)
    member = User.create!(email_address: "member-#{suffix}@example.test", password: SecureRandom.hex(24))
    AccountMerge.create!(guest_user: guest, user: member, status: "pending")

    duplicate = AccountMerge.new(guest_user: guest, user: member, status: "pending")
    refute duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :guest_user_id
  end

  test "guest posts and both sides of the inbox follow the registered account" do
    suffix = SecureRandom.hex(6)
    guest = User.create!(
      email_address: "guest-#{suffix}@guest.local",
      password: SecureRandom.hex(24),
      guest: true
    )
    member = User.create!(
      email_address: "member-#{suffix}@example.test",
      password: SecureRandom.hex(24)
    )
    source_password_digest = guest.password_digest
    post = guest.posts.create!(body: "Anonymous post retained #{suffix}", anonymous: true)
    stale_guest_session = guest.sessions.create!(user_agent: "stale guest browser", ip_address: "127.0.0.1")
    outgoing_body = "Guest to member #{suffix}"
    incoming_body = "Member to guest #{suffix}"
    now = Time.current
    Message.insert_all!([
      { sender_id: guest.id, recipient_id: member.id, body: outgoing_body, created_at: now, updated_at: now },
      { sender_id: member.id, recipient_id: guest.id, body: incoming_body, created_at: now, updated_at: now },
    ])

    result = AccountMerger.new(guest_user: guest, user: member).call

    assert_equal member.id, result.id
    assert_equal member.id, post.reload.user_id
    refute Session.exists?(id: stale_guest_session.id),
           "a guest cookie must not become a registered account session"
    assert post.anonymous?, "a guest post must keep its anonymous presentation after ownership transfer"
    assert_equal [member.id, member.id],
                 [Message.find_by!(body: outgoing_body).sender_id, Message.find_by!(body: incoming_body).recipient_id]
    merge = AccountMerge.find_by!(guest_user_id: guest.id, user_id: member.id)
    assert_equal "merged", merge.status
    assert merge.merged_at.present?
    source = guest.reload
    refute source.guest?
    assert source.deleted_at.present?, "the source row must remain only as an anonymized audit referent"
    assert_match(/\Amerged-#{source.id}-[a-f0-9]+@deleted\.invalid\z/, source.email_address)
    refute_equal source_password_digest, source.password_digest, "the guest password must not remain usable"
    assert_empty Session.where(user_id: source.id)
  end

  test "a non-guest source is a no-op and creates no merge audit" do
    source = User.create!(
      email_address: "source-#{SecureRandom.hex(6)}@example.test",
      password: SecureRandom.hex(24)
    )
    destination = User.create!(
      email_address: "destination-#{SecureRandom.hex(6)}@example.test",
      password: SecureRandom.hex(24)
    )

    result = AccountMerger.new(guest_user: source, user: destination).call

    assert_equal destination.id, result.id
    assert_empty AccountMerge.where(guest_user_id: source.id, user_id: destination.id)
  end

  test "a second destination cannot claim history already merged elsewhere" do
    suffix = SecureRandom.hex(6)
    guest = User.create!(email_address: "guest-#{suffix}@guest.local",
                         password: SecureRandom.hex(24), guest: true)
    first = User.create!(email_address: "first-#{suffix}@example.test", password: SecureRandom.hex(24))
    second = User.create!(email_address: "second-#{suffix}@example.test", password: SecureRandom.hex(24))
    post = guest.posts.create!(body: "Keep this history with the first account #{suffix}", anonymous: true)

    AccountMerger.new(guest_user: guest, user: first).call
    result = AccountMerger.new(guest_user: guest.reload, user: second).call

    assert_equal second.id, result.id
    assert_equal first.id, post.reload.user_id
    assert AccountMerge.exists?(guest_user_id: guest.id, user_id: first.id, status: "merged")
    refute AccountMerge.exists?(guest_user_id: guest.id, user_id: second.id, status: "merged")
  end
end
