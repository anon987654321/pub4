# frozen_string_literal: true
# AN609: Match notification on creation

module MatchNotifications
  extend ActiveSupport::Concern

  included do
    after_create_commit :notify_match_participants
  end

  private

  def notify_match_participants
    [initiator, receiver].each do |user|
      broadcast_append_to "user_#{user.id}", target: "notifications", partial: "dating/matches/overlay", locals: { match: self }
      Conversation.find_or_create_between!(initiator, receiver) if defined?(Conversation)
    end
  end
end