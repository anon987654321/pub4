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

  # ?report=1 is "Report and block": the same decline, plus a report of what
  # the sender wrote and a block, so a spammer is dealt with in one answer
  # rather than three. Only a direct thread has one sender to block.
  def destroy
    reported = params[:report].present? && report_and_block_sender
    @request.destroy!
    redirect_to conversations_path(requests: 1),
                notice: t(reported ? "flash.message_request_reported" : "flash.message_request_declined")
  end

  private

  def report_and_block_sender
    conversation = Conversation.strict_loading(false).find(@request.conversation_id)
    return false unless conversation.direct?

    sender = conversation.other_participants(Current.user).first
    return false unless sender

    report_sender(conversation, sender)
    Current.user.block!(sender)
    true
  end

  # The newest thing they sent is what a moderator reads; a request opened
  # without a message is reported as the person.
  def report_sender(conversation, sender)
    target = Message.where(conversation_id: conversation.id, sender_id: sender.id).last || sender
    report = ModerationWorkflow.report!(reporter: Current.user, target:, reason: "spam",
                                        details: t("messages.request_report_details"))
    ModerationReportNotificationJob.perform_later(report.id) if report.previously_new_record?
  end

  # The reader's own pending membership, in a thread of this city: nobody can
  # accept or decline a request on someone else's behalf.
  def set_request
    @request = ConversationParticipant.requests.joins(:conversation)
                                      .merge(Conversation.current_city_scope)
                                      .where(user_id: Current.user.id, conversation_id: params[:conversation_id])
                                      .take!
  end
end
