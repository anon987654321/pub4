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

  def merge_trust_signals
    guest_user.trust_signals.update_all(user_id: user.id)
  end
end
