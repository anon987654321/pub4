# frozen_string_literal: true

# Accept or decline a message request: a DM from someone the reader has never
# talked to and does not follow. Accepting moves the thread into the inbox and
# lets read receipts and push through. Declining takes the reader out of the
# thread; the sender is not told, the way a request that is never answered
# tells them nothing either, and a block stays one button away on the thread.
class ConversationRequestsController < ApplicationController
  before_action :require_user_session
  before_action :set_request

  def create
    @request.accept!
    redirect_to conversation_path(@request.conversation_id), notice: t("flash.message_request_accepted")
  end

  def destroy
    @request.destroy!
    redirect_to conversations_path(requests: 1), notice: t("flash.message_request_declined")
  end

  private

  # The reader's own pending membership, in a thread of this city: nobody can
  # accept or decline a request on someone else's behalf.
  def set_request
    @request = ConversationParticipant.requests.joins(:conversation)
                                      .merge(Conversation.current_city_scope)
                                      .where(user_id: Current.user.id, conversation_id: params[:conversation_id])
                                      .take!
  end
end
