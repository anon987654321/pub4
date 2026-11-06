# frozen_string_literal: true

class NearbyController < ApplicationController
  DEFAULT_RADIUS_KM = 10.0
  MAX_RADIUS_KM = 25.0

  # Anonymous stranger chat is abuse-prone — cap how fast conversations start.
  rate_limit to: 15, within: 5.minutes, only: %i[create],
    with: -> { redirect_to nearby_path, alert: t("flash.chats_rate_limited") }

  # #widget IS a turbo-frame body. Inside the application layout it answered
  # 64,640 bytes -- including a second copy of the chat widget that requested it
  # -- for the ~2KB frame Turbo then extracts and keeps.
  layout false, only: :widget

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
    return redirect_to(nearby_path, alert: t("flash.location_required_for_nearby")) unless lat && lng

    conversation = Conversation.find_or_create_geo_room(lat: lat, lng: lng)
    # A GET that writes: joining needs an id, and a soft guest may still be
    # unsaved on a first visit (Shared::Authentication#find_or_create_guest_user).
    conversation.join!(ensure_guest_user!)
    redirect_to channel_path(conversation.slug)
  end

  # Compact turbo-frame body for the floating widget (see shared/_nearby_chat_widget).
  # Same join as #room, but renders in place instead of redirecting to the full
  # channel page -- the widget IS the frame, there's nowhere to navigate to.
  #
  # Ambient chat: with GPS → geo room; without → #brgen city lobby inline so
  # anonymous chat works without a second navigation. Soft guests are
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

    # A GET that writes. `me` above may be a soft guest that has not been saved
    # yet — the first uncookied request builds one without persisting it, so a
    # crawl of this page costs no rows. Joining needs an id, so this is where it
    # becomes real; a no-op for a returning visitor or a signed-in user.
    me = ensure_guest_user!
    @conversation.join!(me)
    @conversation.mark_read_for!(me)
    ActsAsTenant.without_tenant do
# messages/_message renders here as well as in a channel and a DM, and it
# reads message_receipts, link_preview, parent.sender, message.conversation
# and the attachment. :sender alone left three queries per message on a
# fifty-message widget; the last two would have left two more.
@messages = @conversation.messages.visible.unexpired
                         .includes(:sender, :message_receipts, :link_preview, :reactions, :conversation,
                                   parent: :sender).with_attached_attachment
                         .order(:created_at).last(50).to_a
    end
    @message = Message.new
  end

  def create
    other = User.messageable.find(params[:user_id])
    refusal = refusal_for(other)
    return redirect_to(nearby_path, alert: t(refusal)) if refusal

    # A stranger nearby is still a stranger: the chat opens as a message request,
    # as conversations#create does, not as an accepted DM.
    conversation = Conversation.find_or_create_direct(Current.user, other, as_request: true)
    redirect_to conversation
  end

  # How far away a stranger is, as shown: a band, never a figure. A distance to
  # 0.1 km from three places pins a person down, so the exact value never leaves
  # this controller, and the list is ordered by band and then by handle rather
  # than by the exact distance it would otherwise leak through its order.
  DISTANCE_BANDS = [ [ 1, "under_1" ], [ 2, "1_to_2" ], [ 5, "2_to_5" ] ].freeze

  def self.distance_band(km)
    DISTANCE_BANDS.find { |limit, _| km < limit }&.last || "over_5"
  end

  def self.band_rank(band) = DISTANCE_BANDS.index { _1.last == band } || DISTANCE_BANDS.size

  private

  # Why a chat with other may not open, as a flash key; nil when it may.
  def refusal_for(other)
    return "flash.thats_you" if other == Current.user
    return "flash.no_longer_nearby" unless in_range?(other)

    # A block either way ends contact here as it does in the messenger.
    "flash.user_not_found" if blocked_ids.include?(other.id)
  end

  # Only people actually in range: the endpoint must not open a DM to an
  # arbitrary user id (enumeration, non-consensual contact).
  def in_range?(other)
    me = Current.user
    me&.latitude && me.longitude && other.distance_to(me.latitude, me.longitude).to_f <= MAX_RADIUS_KM
  end

  def render_widget_shell
    # Empty @conversation: template shows locate / lobby CTAs.
  end

  def radius_km
    value = params[:radius_km].presence || DEFAULT_RADIUS_KM
    value.to_f.clamp(0.5, MAX_RADIUS_KM)
  end

  NEARBY_LIMIT = 100
  # Nearby means now: a location shared weeks ago is not where anyone is.
  LOCATION_FRESH_FOR = 6.hours

  # People the viewer blocks or is blocked by, who are never listed or reachable here.
  def blocked_ids
    me = Current.user
    @blocked_ids ||= me ? me.blocked_user_ids + Block.where(blocked_id: me.id).pluck(:blocker_id) : []
  end

  # The reject/filter_map/sort_by below all happen in Ruby, so the scope has to
  # be bounded before it gets there -- inside a dense city this was every user
  # within the radius, on a 1GB box.
  def nearby_users(lat, lng, radius)
    candidates = User.messageable.located_since(LOCATION_FRESH_FOR.ago)
    candidates = candidates.nearby(lat, lng, radius)
    candidates = candidates.where.not(id: blocked_ids)
    candidates = candidates.limit(NEARBY_LIMIT)
    candidates.reject { |user| user == Current.user }.filter_map do |user|
      distance = user.distance_to(lat, lng)
      next if distance.nil? || distance > radius

      [ user, self.class.distance_band(distance) ]
    end.sort_by { |user, band| [ self.class.band_rank(band), user.anon_handle.to_s ] }
  end
end
