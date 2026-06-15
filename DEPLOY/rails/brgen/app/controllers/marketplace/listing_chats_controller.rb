# frozen_string_literal: true

class Marketplace::ListingChatsController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_listing

  def create
    seller = @listing.user
    if seller == Current.user
      redirect_to marketplace_listing_path(@listing), alert: "You cannot message yourself"
      return
    end

    @conversation = Conversation.find_by(marketplace_listing: @listing, conversation_type: "direct") ||
      Conversation.create!(conversation_type: "direct", marketplace_listing: @listing).tap do |c|
        c.participants << Current.user << seller
      end

    unless @conversation.participants.include?(seller)
      @conversation.participants << seller
    end

    if params[:message].present?
      @conversation.messages.create!(sender: Current.user, content: params[:message], message_type: "text")
    end

    ActivityEventRecorder.call(
      actor: Current.user,
      event_name: "MarketplaceChatStarted",
      object: @listing,
      source_vertical: "marketplace",
      locality: @listing.location
    ) if defined?(ActivityEventRecorder)

    redirect_to @conversation, notice: "Chat with seller opened"
  end

  private

  def set_listing
    @listing = Marketplace::Listing.find(params[:listing_id])
  end
end