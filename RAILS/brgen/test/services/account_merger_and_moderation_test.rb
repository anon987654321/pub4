# frozen_string_literal: true

require "test_helper"

# The other half of the coverage-contract gap: the merge that hands a guest's
# whole history to a real account, and the moderation workflow that resolves a
# report — both money-and-trust paths that had never had a method called.
class AccountMergerAndModerationTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @guest = User.create!(email_address: "g-#{SecureRandom.hex(4)}@guest.local",
                          password: SecureRandom.hex(16), guest: true, city: @city)
    @member = User.create!(email_address: "m-#{SecureRandom.hex(4)}@brgen.no",
                           password: SecureRandom.hex(16), username: "m_#{SecureRandom.hex(3)}", city: @city)
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "a guest and destination pair cannot have duplicate merge audit rows" do
    AccountMerge.create!(guest_user: @guest, user: @member, status: "pending")
    duplicate = AccountMerge.new(guest_user: @guest, user: @member, status: "pending")

    refute duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :guest_user_id
  end

  test "merge hands the guest's posts and signals to the member and records itself" do
    source_password_digest = @guest.password_digest
    post = Post.create!(title: "hei", content: "nabolagsfest på lørdag", user: @guest)
    TrustSignal.create!(user: @guest, kind: "account_created", source: "test", weight: 0)

    result = AccountMerger.new(guest_user: @guest, user: @member).call

    assert_equal @member, result
    assert_equal @member.id, post.reload.user_id
    assert_equal @member.id, TrustSignal.find_by(kind: "account_created").user_id
    merge = AccountMerge.find_by(guest_user_id: @guest.id, user_id: @member.id)
    assert merge, "the merge must leave a record"
    assert_equal "merged", merge.status
    source = @guest.reload
    refute source.guest?, "the source guest must stop being an active guest"
    assert source.deleted_at.present?, "the source row must remain only as an anonymized audit referent"
    assert_match(/\Amerged-#{source.id}-[a-f0-9]+@deleted\.invalid\z/, source.email_address)
    refute_equal source_password_digest, source.password_digest, "the guest password must not remain usable"
    assert_empty Session.where(user_id: source.id)
  end

  test "merging duplicate messenger membership and receipts preserves state without violating unique indexes" do
    conversation = Conversation.create!(conversation_type: "group", city: @city)
    guest_read = 4.hours.ago
    member_read = 2.hours.ago
    guest_pin = 1.day.ago
    guest_mute = 1.hour.ago
    guest_participant = ConversationParticipant.create!(
      conversation_id: conversation.id, user_id: @guest.id, role: "voice",
      last_read_at: guest_read, pinned_at: guest_pin, muted_at: guest_mute
    )
    member_participant = ConversationParticipant.create!(
      conversation_id: conversation.id, user_id: @member.id, role: "member",
      last_read_at: member_read
    )
    message = Message.create!(
      conversation: conversation, sender: @guest,
      content: "History survives account conversion", message_type: "text"
    )
    guest_receipt = MessageReceipt.find_or_create_by!(message_id: message.id, user_id: @guest.id)
    member_receipt = MessageReceipt.find_or_create_by!(message_id: message.id, user_id: @member.id)
    guest_delivered = 3.hours.ago
    member_delivered = 2.hours.ago
    guest_read_at = 30.minutes.ago
    guest_receipt.update_columns(delivered_at: guest_delivered, read_at: guest_read_at)
    member_receipt.update_columns(delivered_at: member_delivered, read_at: nil)
    typing = TypingIndicator.create!(
      conversation_id: conversation.id, user_id: @guest.id, expires_at: 1.minute.from_now
    )

    AccountMerger.new(guest_user: @guest, user: @member).call

    participants = ConversationParticipant.where(conversation_id: conversation.id, user_id: @member.id)
    assert_equal 1, participants.count
    participant = participants.first
    assert_equal "voice", participant.role
    assert_equal member_read.to_i, participant.last_read_at.to_i
    assert_equal guest_pin.to_i, participant.pinned_at.to_i
    assert_equal guest_mute.to_i, participant.muted_at.to_i
    assert_nil participant.archived_at
    refute ConversationParticipant.exists?(id: guest_participant.id)
    assert ConversationParticipant.exists?(id: member_participant.id)
    assert_equal @member.id, message.reload.sender_id

    receipts = MessageReceipt.where(message_id: message.id, user_id: @member.id)
    assert_equal 1, receipts.count
    receipt = receipts.first
    assert_equal guest_delivered.to_i, receipt.delivered_at.to_i, "keep the earliest delivered timestamp"
    assert_equal guest_read_at.to_i, receipt.read_at.to_i, "a read receipt must not become unread"
    refute MessageReceipt.exists?(id: guest_receipt.id)
    refute TypingIndicator.exists?(id: typing.id), "stale guest typing state must be discarded"
    refute TypingIndicator.exists?(user_id: @guest.id)
    assert AccountMerge.exists?(guest_user_id: @guest.id, user_id: @member.id)
  end

  test "merging a non-guest is refused as a no-op" do
    regular = User.create!(email_address: "r-#{SecureRandom.hex(4)}@brgen.no",
                           password: SecureRandom.hex(16), username: "r_#{SecureRandom.hex(3)}", city: @city)
    post = Post.create!(title: "min", content: "dette er mitt innlegg her", user: regular)
    AccountMerger.new(guest_user: regular, user: @member).call
    assert_equal regular.id, post.reload.user_id, "a non-guest's history must never transfer"
    assert_nil AccountMerge.find_by(guest_user_id: regular.id)
  end

  test "a report opens a flag and resolving it closes the flag and removes the content" do
    post = Post.create!(title: "spam", content: "kjøp klokker billig nå her", user: @guest)
    report = ModerationWorkflow.report!(reporter: @member, target: post, reason: "spam")

    assert_equal "open", report.status
    flag = ModerationFlag.find_by(flaggable: post)
    assert flag, "reporting must flag the content"
    assert_equal "open", flag.status

    ModerationWorkflow.transition!(report: report, status: "resolved", decision_reason: "spam policy")
    report.reload
    assert_equal "resolved", report.status
    assert_equal "spam policy", report.decision_reason
    assert report.decided_at.present?
    assert_equal "resolved", flag.reload.status
    # remove_content: however the model spells removal, the feed must not show it.
    assert_not Post.where(id: post.id).where(deleted_at: nil).exists? if Post.column_names.include?("deleted_at")
  end

  test "transition! survives a report loaded bare by id — the strict_loading trap" do
    post = Post.create!(title: "spam2", content: "enda mer spam om klokker", user: @guest)
    report = ModerationWorkflow.report!(reporter: @member, target: post, reason: "spam")
    bare = ModerationReport.find(report.id)
    assert_nothing_raised { ModerationWorkflow.transition!(report: bare, status: "resolved") }
  end

  test "an unknown status is refused without touching the report" do
    post = Post.create!(title: "x", content: "helt vanlig innhold her ja", user: @guest)
    report = ModerationWorkflow.report!(reporter: @member, target: post, reason: "other")
    ModerationWorkflow.transition!(report: report, status: "not_a_status")
    assert_equal "open", report.reload.status
  end
end
