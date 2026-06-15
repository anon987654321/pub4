# frozen_string_literal: true

class MentionMailer < ApplicationMailer
  def mention(notification_id)
    @notification = Notification.find(notification_id)
    @mention = @notification.notifiable
    @actor_name = @notification.actor&.display_name || "Someone"
    @mention_url = mention_url_for(@mention)
    mail(to: @notification.user.email_address, subject: "#{@actor_name} mentioned you on Brgen")
  end

  private

  def mention_url_for(mention)
    target = mention
    target = target.commentable while target.respond_to?(:commentable) && !target.is_a?(Post)
    polymorphic_url(target)
  end
end
