# frozen_string_literal: true

class TypingIndicatorsController < ApplicationController
  before_action :require_user_session

  # The client throttles to one ping every two seconds; this is the server's
  # bound on the busiest endpoint in the messenger.
  rate_limit to: 40, within: 1.minute, only: :create, name: "typing",
    by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip },
    with: -> { head :too_many_requests }

  # "Typing…" is a signal into someone's thread, so it obeys the same rules as
  # a message: nothing across a block, and nothing from someone whose request
  # has not been accepted.
  def create
    conversation = Conversation.for_user(current_user).find(params[:conversation_id])
    return head(:not_found) if conversation.blocked_between?(current_user) || pending_request?(conversation)

    TypingIndicator.set!(conversation:, user: current_user)
    head :ok
  end

  private

  def pending_request?(conversation)
    conversation.conversation_participants.requests.exists?(user_id: current_user.id)
  end
end
