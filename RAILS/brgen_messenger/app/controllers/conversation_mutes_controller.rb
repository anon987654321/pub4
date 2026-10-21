# frozen_string_literal: true

# Mute a thread for yourself: no push, no badge. Archive is the sibling that
# takes it off the list. Neither tells the other side anything.
class ConversationMutesController < ApplicationController
  before_action :require_user_session
  before_action :set_participant

  def create
    @participant.update!(muted_at: Time.current)
    redirect_back fallback_location: conversations_path, notice: t("flash.conversation_muted")
  end

  def destroy
    @participant.update!(muted_at: nil)
    redirect_back fallback_location: conversations_path, notice: t("flash.conversation_unmuted")
  end

  private

  # Membership and city ownership are both required; shared accounts must not
  # mutate mute state for a thread from another city's host.
  def set_participant
    @participant = ConversationParticipant.joins(:conversation)
                                          .merge(Conversation.current_city_scope)
                                          .where(user_id: Current.user.id, conversation_id: params[:conversation_id])
                                          .take!
  end
end
