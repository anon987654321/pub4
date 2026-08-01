# frozen_string_literal: true

class NearbyController < ApplicationController
  DEFAULT_RADIUS_KM = 10.0
  MAX_RADIUS_KM = 25.0

  # Anonymous stranger chat is abuse-prone — cap how fast conversations start.
  rate_limit to: 15, within: 5.minutes, only: %i[create],
    with: -> { redirect_to nearby_path, alert: "Slow down — too many chats started. Try again shortly." }

  def index
    lat = Current.user&.latitude
    lng = Current.user&.longitude
    @located = lat.present?
    @radius_km = radius_km
    @nearby = @located ? nearby_users(lat, lng, @radius_km) : []
  end

  # Shared, anonymous, radius-scoped group room -- everyone currently within
  # ~10km lands in the same room (grid-cell bucketed; see
  # Shared::GeoLocatable.cell_id), unlike #create's 1:1 direct chats.
  def room
    lat = Current.user&.latitude
    lng = Current.user&.longitude
    return redirect_to(nearby_path, alert: "Enable location to join the nearby chat room.") unless lat && lng

    conversation = Conversation.find_or_create_geo_room(lat: lat, lng: lng)
    conversation.join!(Current.user)
    redirect_to channel_path(conversation.slug)
  end

  # Compact turbo-frame body for the floating widget (see shared/_nearby_chat_widget).
  # Same join as #room, but renders in place instead of redirecting to the full
  # channel page -- the widget IS the frame, there's nowhere to navigate to.
  #
  # Ambient chat: with GPS → geo room; without → #brgen city lobby inline so
  # anonymous chat "just works" without a second navigation. Soft guests are
  # the identity path (Craigslist-style); never require signup here.
  def widget
    me = Current.user
    @messages = []
    @lobby = false
    return render_widget_shell unless me

    lat = me.latitude
    lng = me.longitude
    @located = lat.present? && lng.present?

    @conversation =
      if @located
        Conversation.find_or_create_geo_room(lat: lat, lng: lng)
      else
        @lobby = true
        Conversation.find_or_create_channel("brgen", city: Current.city_record)
      end
    return render_widget_shell unless @conversation

    @conversation.join!(me)
    @conversation.mark_read_for!(me)
    ActsAsTenant.without_tenant do
      @messages = @conversation.messages.unexpired.includes(:sender).order(:created_at).last(50).to_a
    end
    @message = Message.new
  end

  def create
    other = User.find(params[:user_id])
    return redirect_to(nearby_path, alert: "That's you.") if other == Current.user

    # Only start chats with people actually in range — don't let the endpoint
    # open a DM to an arbitrary user id (enumeration / non-consensual contact).
    lat = Current.user&.latitude
    lng = Current.user&.longitude
    in_range = lat && lng && other.distance_to(lat, lng).to_f <= MAX_RADIUS_KM
    return redirect_to(nearby_path, alert: "That person isn't nearby anymore.") unless in_range

    conversation = Conversation.find_or_create_direct(Current.user, other)
    redirect_to conversation
  end

  private

  def render_widget_shell
    # Empty @conversation: template shows locate / lobby CTAs.
  end

  def radius_km
    value = params[:radius_km].presence || DEFAULT_RADIUS_KM
    value.to_f.clamp(0.5, MAX_RADIUS_KM)
  end

  def nearby_users(lat, lng, radius)
    User.nearby(lat, lng, radius).reject { |user| user == Current.user }.filter_map do |user|
      distance = user.distance_to(lat, lng)
      next if distance.nil? || distance > radius

      [ user, distance ]
    end.sort_by(&:last)
  end
end
