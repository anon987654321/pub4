class ConversationsController < ApplicationController
  before_action :require_user_session

  def index
    @conversations = Conversation.for_user(Current.user)
                                 .includes(:participants, :messages)
                                 .order("messages.created_at DESC")
  end

  def show
    @conversation = Conversation.for_user(Current.user).find(params[:id])
    @conversation.mark_read_for!(Current.user)
    @messages = @conversation.messages.recent.limit(50).reverse
    @message  = Message.new
  end

  def create
    other         = User.find(params[:user_id])
    @conversation = Conversation.find_or_create_direct(Current.user, other)
    redirect_to @conversation
  end
end
