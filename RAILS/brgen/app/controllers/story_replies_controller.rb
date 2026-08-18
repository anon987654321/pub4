# frozen_string_literal: true

# Answering a story. The reply is a direct message carrying the story it
# answers, so it is still readable after the 24 hours are up — which is the
# point, because the story will not be.
class StoryRepliesController < ApplicationController
  before_action :require_user_session

  def create
    # alive, not find: a story that has expired is gone for every other surface,
    # and a reply box that still works after the sweep is a promise broken
    # quietly.
    story = Story.alive.find(params[:story_id])
    author = User.find(story.user_id)

    return redirect_to(stories_path, alert: t("flash.story_reply_self")) if author.id == Current.user.id
    return redirect_to(stories_path, alert: t("flash.user_not_found")) if blocked_either_way?(author)

    conversation = Conversation.find_or_create_direct(Current.user, author)
    message = conversation.messages.new(
      sender: Current.user, content: params[:content].to_s.strip, message_type: "text", story: story
    )
    if message.save
      redirect_to conversation_path(conversation), notice: t("flash.story_replied")
    else
      redirect_to story_path(story), alert: t("flash.story_reply_failed")
    end
  end

  private

  def blocked_either_way?(other)
    return false unless Current.user.respond_to?(:blocking?)

    Current.user.blocking?(other) || (other.respond_to?(:blocking?) && other.blocking?(Current.user))
  end
end
