# frozen_string_literal: true

class Mention < ApplicationRecord
  belongs_to :mentionable, polymorphic: true
  belongs_to :mentioned_user

  after_create_commit :notify_mentioned_user

  private

  def notify_mentioned_user
    actor = mentionable.try(:user)
    return if actor.blank? || actor == mentioned_user

    notification = Notification.create!(
      user: mentioned_user,
      actor: actor,
      kind: "mention",
      notifiable: mentionable
    )
    case mentioned_user.mention_notification_delivery_mode
    when "email"
      MentionMailer.mention(notification.id).deliver_later
    end
  end
end
