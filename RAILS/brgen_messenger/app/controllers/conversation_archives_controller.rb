# frozen_string_literal: true

# Put a thread away, and bring it back. A new message from the other side brings
# it back on its own (Message#resurface_for_recipients), so archiving is a way to
# tidy the list and never a way to miss a reply.
class ConversationArchivesController < ApplicationController
  before_action :require_user_session
  before_action :set_participant

  def create
    @participant.update!(archived_at: Time.current)
    redirect_to conversations_path, notice: t("flash.conversation_archived")
  end

  def destroy
    @participant.update!(archived_at: nil)
    redirect_back fallback_location: conversations_path, notice: t("flash.conversation_unarchived")
  end

  private

  def set_participant
    @participant = ConversationParticipant.where(user_id: Current.user.id)
                                          .find_by!(conversation_id: params[:conversation_id])
  end
end
