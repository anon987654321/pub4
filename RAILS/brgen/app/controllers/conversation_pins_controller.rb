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

  # The viewer's own participant row is both the thing being pinned and the
  # membership check: someone who is not in the conversation has no row, so they
  # get a 404 rather than a pin on a thread they cannot read.
  def set_participant
    @participant = ConversationParticipant.where(user_id: Current.user.id)
                                          .find_by!(conversation_id: params[:conversation_id])
  end
end
