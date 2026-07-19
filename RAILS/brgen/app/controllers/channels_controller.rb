# frozen_string_literal: true

# Public IRC-style rooms. A channel is a group Conversation resolved by slug
# (see Conversation::CHANNELS); posting reuses MessagesController, so only signed
# -in users write — everyone shows up under an anonymous handle, bots under their
# persona name.
class ChannelsController < ApplicationController
  def index
    @channels = Conversation.channels.index_by(&:slug)
  end

  def show
    @conversation = Conversation.find_or_create_channel(params[:slug])
    return redirect_to(channels_path, alert: "No such channel.") unless @conversation

    if authenticated?
      @conversation.join!(Current.user)
      @conversation.mark_read_for!(Current.user)
    end

    ActsAsTenant.without_tenant do
      @messages = @conversation.messages.unexpired.includes(:sender).order(:created_at).last(100).to_a
    end
    @message = Message.new
  end
end
