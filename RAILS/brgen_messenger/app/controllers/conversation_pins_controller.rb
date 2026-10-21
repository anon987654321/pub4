# frozen_string_literal: true

# Pin a thread to the top of your own messenger list, and take it down again.
class ConversationPinsController < ApplicationController
  before_action :require_user_session
  before_action :set_participant

  def create
    @participant.update!(pinned_at: Time.current)
    redirect_back fallback_location: conversations_path, notice: t("flash.conversation_pinned")
  end

  def destroy
    @participant.update!(pinned_at: nil)
    redirect_back fallback_location: conversations_path, notice: t("flash.conversation_unpinned")
  end

  private

  # Membership and city ownership are both required. A shared user identity
  # must not let another city's host mutate this thread's personal ordering.
  def set_participant
    @participant = ConversationParticipant.joins(:conversation)
                                          .merge(Conversation.current_city_scope)
                                          .where(user_id: Current.user.id, conversation_id: params[:conversation_id])
                                          .take!
  end
end
