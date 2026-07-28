# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :require_user_session
  before_action :set_conversation

  rate_limit to: 40, within: 3.minutes, only: :create,
    with: -> { redirect_back fallback_location: root_path, alert: "Slow down — too many messages. Try again shortly." }

  def create
    @message        = @conversation.messages.build(message_params)
    @message.sender = Current.user

    if @message.save

      @conversation.participants.excluding(Current.user).each do |recipient|
        next if recipient.guest? # guests have no durable push endpoint

        Shared::Pushable.push_to(recipient,
          title: Current.user.display_name,
          body:  @message.content.to_s.truncate(120),
          url:   conversation_path(@conversation)
        )
      end
      respond_to do |format|
        # The corner chat widget and the full channel page post to the same
        # endpoint but own different composers; answering with the page form
        # would replace the widget's compact one with page-sized markup.
        format.turbo_stream { render from_widget? ? :create_widget : :create }
        format.html { redirect_to @conversation }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def from_widget? = params[:origin] == "widget"

  def set_conversation
    @conversation = Conversation.for_user(Current.user).find(params[:conversation_id])
  end

  def message_params
    params.require(:message).permit(:content, :message_type)
  end
end
