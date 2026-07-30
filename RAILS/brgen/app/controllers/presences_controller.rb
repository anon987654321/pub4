# frozen_string_literal: true

# Heartbeat endpoint for "who has this room open".
#
# Mirrors TypingIndicatorsController: nested under a conversation, create-only,
# fire-and-forget. head :no_content rather than a body -- the count reaches every
# reader over the conversation's Turbo stream, so the beat itself has nothing to
# say back and shouldn't pay for a render 3x a minute per reader.
class PresencesController < ApplicationController
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

  def set_conversation
    @conversation = Conversation.find(params[:conversation_id])
  end
end
