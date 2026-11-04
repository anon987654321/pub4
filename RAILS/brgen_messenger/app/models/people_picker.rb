# frozen_string_literal: true

# Who the new-conversation picker offers first: people the viewer follows or
# already has a direct thread with, then everyone else, newest first. Newest
# signups alone put strangers above the people the viewer actually knows.
module PeoplePicker
  module_function

  def rank(scope, viewer)
    known = known_ids(viewer)
    return scope.order(created_at: :desc) if known.empty?

    first = ActiveRecord::Base.sanitize_sql_array([ "CASE WHEN users.id IN (?) THEN 0 ELSE 1 END", known ])
    scope.order(Arel.sql(first)).order(created_at: :desc)
  end

  def known_ids(viewer)
    followed = Follow.where(follower_id: viewer.id).pluck(:followed_id)
    threads = Conversation.for_user(viewer).where(conversation_type: "direct").select(:id)
    talked = ConversationParticipant.where(conversation_id: threads).where.not(user_id: viewer.id).pluck(:user_id)
    (followed + talked).uniq
  end
end
