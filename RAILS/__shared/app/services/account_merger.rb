# frozen_string_literal: true

# Transfers the user-owned history of a persisted guest to a registered
# account. Shared signup and OAuth use this one transaction, while optional
# associations keep the contract portable across Brgen and Amber: Brgen owns
# conversation participants/trust signals; Amber owns direct messages.
class AccountMerger
  def initialize(guest_user:, user:)
    @guest_user = guest_user
    @user = user
  end

  def call
    return user if guest_user == user
    return user unless guest_user.respond_to?(:guest?) && guest_user.guest?

    ActiveRecord::Base.transaction do
      # Serialize two tabs completing signup/OAuth for the same guest. The
      # second waiter rechecks the locked row instead of moving the same rows
      # or colliding with the unique audit index.
      guest_user.lock!
      user.lock!
      next unless guest_user.guest?

      merge_posts
      merge_comments
      merge_conversations
      merge_messages
      merge_trust_signals
      merge_moderation_flags
      merge_sessions
      record_merge
      guest_user.update!(guest: false) if guest_user.respond_to?(:guest=)
    end

    user
  end

  private

  attr_reader :guest_user, :user

  def merge_posts = move_owned_rows(:posts)

  def merge_comments = move_owned_rows(:comments)

  def merge_conversations = move_owned_rows(:conversation_participants)

  def merge_sessions = move_owned_rows(:sessions)

  # Amber's one-to-one inbox stores the guest on either side of a message;
  # move both directions so signing up preserves the full conversation. Brgen
  # stores messages under conversations, whose participants are moved above.
  def merge_messages
    return unless defined?(::Message) && ::Message.table_exists?

    columns = ::Message.column_names
    ::Message.where(sender_id: guest_user.id).update_all(sender_id: user.id) if columns.include?("sender_id")
    ::Message.where(recipient_id: guest_user.id).update_all(recipient_id: user.id) if columns.include?("recipient_id")
  end

  def merge_moderation_flags
    return unless guest_user.respond_to?(:moderation_flags)
    return unless defined?(::ModerationFlag) && ::ModerationFlag.table_exists?

    guest_user.moderation_flags.update_all(user_id: user.id)
  end

  # The guest and destination can hold the same signal. A bare move would
  # violate the unique index and roll back the entire account conversion.
  def merge_trust_signals
    return unless guest_user.respond_to?(:trust_signals)
    return unless defined?(::TrustSignal) && ::TrustSignal.table_exists?

    ::TrustSignal.where(user_id: guest_user.id)
                 .where(
                   "EXISTS (SELECT 1 FROM trust_signals kept WHERE kept.user_id = :keeper " \
                   "AND kept.kind = trust_signals.kind AND kept.source IS trust_signals.source)",
                   keeper: user.id
                 ).delete_all
    guest_user.trust_signals.update_all(user_id: user.id)
  end

  def record_merge
    unless defined?(::AccountMerge) && ::AccountMerge.table_exists?
      raise ActiveRecord::MigrationError, "account_merges table unavailable; refusing guest history transfer"
    end

    ::AccountMerge.create!(
      guest_user: guest_user,
      user: user,
      status: "merged",
      merged_at: Time.current
    )
  end

  def move_owned_rows(association)
    return unless guest_user.respond_to?(association)

    relation = guest_user.public_send(association)
    relation.update_all(user_id: user.id) if relation.respond_to?(:update_all)
  end
end
