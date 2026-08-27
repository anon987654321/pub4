# frozen_string_literal: true

# Public IRC-style rooms. A channel is a group Conversation resolved by slug
# (see Conversation::CHANNELS); posting reuses MessagesController. Guests and
# signed-in users both write — humans show as anonymous handles, bots as personas.
class ChannelsController < ApplicationController
  def index
    @city = Current.city_record
rooms = Conversation.channels.where(city_id: @city&.id).to_a
@channels = rooms.index_by(&:slug)
# Two queries for the whole list rather than two per room.
@message_counts = Conversation.message_counts_for(rooms)
@active_counts = Conversation.active_counts_for(rooms)
  end

  def show
    @conversation = if Conversation.geo_room_slug?(params[:slug])
                      # Never create from a URL-guessed slug -- geo rooms are only
                      # created by NearbyController#room from the visitor's own
                      # real stored location.
                      Conversation.find_by(slug: params[:slug], city_id: nil)
    else
                      Conversation.find_or_create_channel(params[:slug], city: Current.city_record)
    end
    return redirect_to(channels_path, alert: t("flash.no_such_channel")) unless @conversation

    if Current.user.present?
      # A GET that writes. ensure_guest_user! persists a soft guest that is still
      # unsaved on a first visit; a no-op for everyone else.
      me = ensure_guest_user!
      @conversation.join!(me)
      @conversation.mark_read_for!(me)
    end

    ActsAsTenant.without_tenant do
      @messages = @conversation.messages.visible.unexpired.includes(:sender).order(:created_at).last(100).to_a
    end
    @message = Message.new
  end
end
