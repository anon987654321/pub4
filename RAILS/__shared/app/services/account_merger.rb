# frozen_string_literal: true

require "bcrypt"
require "securerandom"
# Transfers the user-owned history of a persisted guest to a registered
# account. Shared signup and OAuth use this one transaction, while optional
# associations keep the contract portable across Brgen and Amber: Brgen owns
# conversations, channel messages and trust signals; Amber owns direct inboxes.
# Guest sessions are invalidated, never promoted into registered credentials.
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
      invalidate_guest_sessions
      record_merge
      retire_guest_source
    end

    user
  end

  private

  attr_reader :guest_user, :user

  def merge_posts = move_owned_rows(:posts)

  def merge_comments = move_owned_rows(:comments)

  # Conversation membership and receipts both have pair-unique indexes. Merge them
  # by their natural key instead of a bulk user_id update, which would fail when
  # the registered account already belongs to the same thread.
  def merge_conversations
    reflection = guest_user.class.reflect_on_association(:conversation_participants)
    if reflection&.macro == :has_many
      model = reflection.klass
      if model.table_exists? && %w[user_id conversation_id].all? { |column| model.column_names.include?(column) }
        model.where(user_id: guest_user.id).find_each do |source|
          destination = model.find_by(conversation_id: source.conversation_id, user_id: user.id)
          if destination
            merge_participant_state(destination, source, model)
            source.delete
          else
            source.update_columns(user_id: user.id, updated_at: Time.current)
          end
        end
      end
    end
    merge_message_receipts
    clear_guest_typing_indicators
  end

  def merge_participant_state(destination, source, model)
    columns = model.column_names
    values = {}
    if columns.include?("last_read_at")
      values[:last_read_at] = [destination.last_read_at, source.last_read_at].compact.max
    end
    %i[pinned_at muted_at].each do |column|
      next unless columns.include?(column.to_s)

      values[column] = [destination.public_send(column), source.public_send(column)].compact.max
    end
    if columns.include?("archived_at")
      # Keep the thread visible if either identity had it in the inbox.
      archive_times = [destination.archived_at, source.archived_at]
      values[:archived_at] = archive_times.all?(&:present?) ? archive_times.compact.max : nil
    end
    if columns.include?("role") && model.const_defined?(:RANK, false)
      rank = model.const_get(:RANK)
      values[:role] = [destination.role, source.role].max_by { |role| rank.fetch(role, 0) }
    end
    values[:updated_at] = Time.current if columns.include?("updated_at")
    destination.update_columns(values) unless values.empty?
  end

  # At least one identity may have read or received the same message. Keep that
  # fact on the surviving receipt rather than colliding with the unique index.
  def merge_message_receipts
    reflection = guest_user.class.reflect_on_association(:message_receipts)
    return unless reflection&.macro == :has_many

    model = reflection.klass
    return unless model.table_exists? && %w[user_id message_id].all? { |column| model.column_names.include?(column) }

    model.where(user_id: guest_user.id).find_each do |source|
      destination = model.find_by(message_id: source.message_id, user_id: user.id)
      if destination
        values = {}
        %w[delivered_at read_at].each do |column|
          next unless model.column_names.include?(column)

          times = [destination.public_send(column), source.public_send(column)].compact
          values[column] = times.min if times.any?
        end
        values[:updated_at] = Time.current if model.column_names.include?("updated_at")
        destination.update_columns(values) unless values.empty?
        source.delete
      else
        values = { user_id: user.id }
        values[:updated_at] = Time.current if model.column_names.include?("updated_at")
        source.update_columns(values)
      end
    end
  end

  # Typing state is ephemeral, not account history. Invalidate it rather than
  # carrying a stale "is typing" signal into the authenticated account.
  def clear_guest_typing_indicators
    reflection = guest_user.class.reflect_on_association(:typing_indicators)
    return unless reflection&.macro == :has_many

    model = reflection.klass
    return unless model.table_exists? && model.column_names.include?("user_id")

    model.where(user_id: guest_user.id).delete_all
  end

  # A guest cookie is not an authenticated-account credential. Destroy its
  # session rows when history transfers; moving them would upgrade every copy
  # of an old guest cookie into the new registered identity.
  def invalidate_guest_sessions
    unless defined?(::Session) && ::Session.table_exists?
      raise ActiveRecord::MigrationError, "sessions table unavailable; refusing guest session promotion"
    end

    # Query by foreign key rather than lazily reading guest_user.sessions:
    # strict loading is enabled throughout the apps and should not turn a
    # security boundary into a silent skipped transfer.
    ::Session.where(user_id: guest_user.id).find_each(&:destroy!)
  end

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
    return unless defined?(::ModerationFlag) && ::ModerationFlag.table_exists?
    return unless ::ModerationFlag.column_names.include?("user_id")

    ::ModerationFlag.where(user_id: guest_user.id).update_all(user_id: user.id)
  end

  # The guest and destination can hold the same signal. A bare move would
  # violate the unique index and roll back the entire account conversion.
  # Query by foreign key, not guest_user.trust_signals: strict loading is on in
  # both hosts and a lazy association read must not silently stop account merge.
  def merge_trust_signals
    return unless defined?(::TrustSignal) && ::TrustSignal.table_exists?

    ::TrustSignal.where(user_id: guest_user.id)
                 .where(
                   "EXISTS (SELECT 1 FROM trust_signals kept WHERE kept.user_id = :keeper " \
                   "AND kept.kind = trust_signals.kind AND kept.source IS trust_signals.source)",
                   keeper: user.id
                 ).delete_all
    ::TrustSignal.where(user_id: guest_user.id).update_all(user_id: user.id)
  end

  # Keep the audit's foreign-key referent, but never turn a synthetic guest
  # row into an ordinary account. Its sessions are already revoked; clear its
  # login material and anonymise it so it cannot be authenticated later.
  def retire_guest_source
    attributes = {
      guest: false,
      deleted_at: Time.current,
      deletion_scheduled_at: nil,
      email_address: "merged-#{guest_user.id}-#{SecureRandom.hex(6)}@deleted.invalid",
      password_digest: BCrypt::Password.create(SecureRandom.hex(32), cost: BCrypt::Engine::MIN_COST),
      email_verified_at: nil,
      email_verification_token: nil,
      magic_link_token: nil,
      magic_link_expires_at: nil,
      remember_token: nil,
      remember_token_expires_at: nil,
      otp_secret: nil,
      two_factor_enabled: false,
      updated_at: Time.current
    }
    attributes.select! { |column, _value| guest_user.has_attribute?(column) }
    guest_user.update_columns(attributes)
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
    reflection = guest_user.class.reflect_on_association(association)
    return unless reflection&.macro == :has_many && !reflection.options[:through]

    model = reflection.klass
    foreign_key = reflection.foreign_key.to_s
    return unless model.table_exists? && model.column_names.include?(foreign_key)

    model.where(foreign_key => guest_user.id).update_all(foreign_key => user.id)
  end
end
