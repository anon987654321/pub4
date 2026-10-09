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

  # The viewer's own participant row is the thing being muted and the membership
  # check at once, as for the pin: no row, no thread, a 404.
  def set_participant
    @participant = ConversationParticipant.where(user_id: Current.user.id)
                                          .find_by!(conversation_id: params[:conversation_id])
  end
end
