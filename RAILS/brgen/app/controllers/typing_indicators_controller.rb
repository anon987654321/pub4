# frozen_string_literal: true

class TypingIndicatorsController < ApplicationController
  before_action :authenticate_user!

  def create
    conversation = Conversation.for_user(current_user).find(params[:conversation_id])
    TypingIndicator.set!(conversation:, user: current_user)
    head :ok
  end
end
