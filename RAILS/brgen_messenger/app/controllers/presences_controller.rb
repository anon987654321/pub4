# frozen_string_literal: true

# Heartbeat endpoint for "who has this room open".
#
# Mirrors TypingIndicatorsController: nested under a conversation, create-only,
# fire-and-forget. head :no_content rather than a body -- the count reaches every
# reader over the conversation's Turbo stream, so the beat itself has nothing to
# say back and shouldn't pay for a render 3x a minute per reader.
class PresencesController < ApplicationController
  before_action :require_user_session
  before_action :set_conversation

  def create
    ChannelPresence.touch!(conversation: @conversation, user: Current.user)
    head :no_content
  end

  # Sent on pagehide/turbo:before-visit so a leaver disappears immediately
  # instead of lingering for the TTL.
  def destroy
    ChannelPresence.leave!(conversation: @conversation, user: Current.user)
    head :no_content
  end

  private

  # Scoped through the participant join, exactly as TypingIndicatorsController
  # does it. An unscoped Conversation.find let anyone who knew a conversation id
  # beat into a room they are not in — and since the beat broadcasts the roster
  # to every reader, that showed a stranger as present in a private thread.
  def set_conversation
    @conversation = Conversation.for_user(Current.user).find(params[:conversation_id])
  end
end
