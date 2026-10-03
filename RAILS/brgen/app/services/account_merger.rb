# frozen_string_literal: true

class AccountMerger
  def initialize(guest_user:, user:)
    @guest_user = guest_user
    @user = user
  end

  def call
    return user if guest_user == user
    return user unless guest_user.guest?

    ActiveRecord::Base.transaction do
      merge_posts
      merge_comments
      merge_conversations
      merge_trust_signals
      merge_moderation_flags
      merge_sessions

      AccountMerge.create!(
        guest_user: guest_user,
        user: user,
        status: "merged",
        merged_at: Time.current
      )

      guest_user.update!(guest: false)
    end

    user
  end

  private

  attr_reader :guest_user, :user

  def merge_comments
    guest_user.comments.update_all(user_id: user.id)
  end

  def merge_conversations
    guest_user.conversation_participants.update_all(user_id: user.id)
  end

  def merge_moderation_flags
    guest_user.moderation_flags.update_all(user_id: user.id)
  end

  def merge_posts
    guest_user.posts.update_all(user_id: user.id)
  end

  def merge_sessions
    guest_user.sessions.update_all(user_id: user.id)
  end

  # The guest and the account it merges into can hold the same signal — both
  # were granted `guest_verified` from the same source, both were reported for
  # the same post. A bare update_all moved them across and the account ended up
  # counting one proof twice; since 20260825120000 it raises RecordNotUnique
  # instead. Drop the guest's copy where the account already has one, then move
  # the rest.
  # `IS`, not `=`: source is nullable and SQLite's `=` is never true for NULL,
  # so two sourceless signals of the same kind would not match and the move
  # would still collide. Expressed in SQL rather than Ruby because every other
  # merge_* here works on an unloaded relation — guest_user arrives
  # strict_loading and enumerating the association raises.
  def merge_trust_signals
    TrustSignal.where(user_id: guest_user.id)
               .where(
                 "EXISTS (SELECT 1 FROM trust_signals kept WHERE kept.user_id = :keeper " \
                 "AND kept.kind = trust_signals.kind AND kept.source IS trust_signals.source)",
                 keeper: user.id
               ).delete_all
    guest_user.trust_signals.update_all(user_id: user.id)
  end
end
