# frozen_string_literal: true

class Conversation < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  belongs_to :city, optional: true
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy
  has_many :typing_indicators, dependent: :destroy

  validates :conversation_type, inclusion: { in: %w[direct group] }

  scope :for_user, ->(u) { joins(:conversation_participants).where(conversation_participants: { user: u }) }
  scope :channels, -> { where(conversation_type: "group").where.not(slug: nil).order(:slug) }

  # Public IRC-style rooms — one per vertical, plus a city-wide lobby. Each is a
  # group Conversation looked up by its stable slug. `bots` names the personas
  # (see ChannelBot::PERSONAS) that hang out there.
  CHANNELS = {
    "brgen" => { name: "#brgen",       vertical: nil,           blurb: "The city-wide lobby — anything goes.",              bots: %w[master echo] },
    "marketplace" => { name: "#marketplace", vertical: "marketplace", blurb: "Buying, selling, haggling, and finds.",              bots: %w[curator echo] },
    "dating" => { name: "#dating",      vertical: "dating",      blurb: "Flirt, vent, and swap first-date ideas.",           bots: %w[cupid echo] },
    "playlist" => { name: "#playlist",    vertical: "playlist",    blurb: "Now playing — share tracks and listening parties.", bots: %w[dj echo] },
    "tv" => { name: "#tv",          vertical: "tv",          blurb: "Live threads for shows and streams.",               bots: %w[critic echo] },
    "takeaway" => { name: "#takeaway",    vertical: "takeaway",    blurb: "What's good to order right now?",                   bots: %w[foodie echo] },
    "maps" => { name: "#maps",        vertical: "maps",        blurb: "Local spots, tips, and directions.",                bots: %w[scout echo] }
  }.freeze

  # Channels are ephemeral: messages fade so a room reads as "what's happening
  # now" rather than an endless scrollback. Reuses the disappearing-message
  # machinery (Message#schedule_expiration + MessageExpirationJob).
  CHANNEL_TTL = ENV.fetch("BRGEN_CHANNEL_TTL_SECONDS", (6 * 3600).to_s).to_i

  def self.channel_slug?(slug) = CHANNELS.key?(slug.to_s)

  # The room's one-line description, in the reader's language.
  #
  # `blurb:` above stays as the English source string and as the fallback, but
  # nothing user-facing may read it directly: the channels index, the room
  # header, the IRC topic and ChannelBot's welcome line all render to visitors
  # of a Norwegian site, and all four printed the constant.
  def self.channel_blurb(slug)
    slug = slug.to_s
    I18n.t("channels.blurb.#{slug}", default: CHANNELS.dig(slug, :blurb).to_s)
  end

  # Idempotently resolve a channel by slug, seeding its bots + a welcome line
  # the first time it is opened.
  # `includes(:city)` is load-bearing, not a query tweak: ApplicationRecord sets
  # strict_loading_by_default, and channel_title reads `city`. A tenant-less
  # room has city_id = nil, where belongs_to answers nil without ever touching
  # the association — so the whole city-scoped path (i.e. production) raised
  # StrictLoadingViolationError on every room open while the tenant-less tests
  # stayed green. Preload it here, and hand `create!` the record rather than the
  # id so a freshly seeded room comes back with the target already in memory.
  def self.find_or_create_channel(slug, city: nil)
    slug = slug.to_s
    spec = CHANNELS[slug] or return nil
    existing = includes(:city).find_by(slug: slug, city_id: city&.id)
    return create_channel!(slug, spec, city) unless existing

    rewelcome_if_empty!(existing)
    existing
  end

  # A channel that has fallen silent is indistinguishable from a broken one.
  #
  # ChannelBot.welcome! runs once, inside create_channel!, and its three posts
  # inherit the room's own CHANNEL_TTL (6h default) like every other channel
  # message. So six hours after a room is created it is empty, and stays empty
  # for good unless a human happens to speak into a page that gives them no
  # reason to. Observed on production #brgen: correct chrome, real roster
  # (@master +echo), topic line, and not one message.
  #
  # Re-seeding on open rather than exempting the welcome from expiry, because a
  # permanent pinned "say hi" would still be sitting above a real conversation a
  # year later. This way the greeting ages out the moment the room has actual
  # traffic, and comes back only when it is the only thing that would be there.
  def self.rewelcome_if_empty!(channel)
    return unless channel.channel?
    return if channel.messages.unexpired.exists?

    ChannelBot.welcome!(channel)
  rescue StandardError => e
    # Opening a room must not 500 because the greeting failed. Surfaced rather
    # than swallowed: a silent rescue here would hide the same emptiness this
    # method exists to fix.
    Rails.logger.warn("conversation:rewelcome_failed slug=#{channel.slug} #{e.class}: #{e.message}")
  end

  def self.create_channel!(slug, spec, city)
    transaction do
      channel = create!(conversation_type: "group", slug: slug, city: city,
                        name: spec[:name], vertical: spec[:vertical], disappearing_duration: CHANNEL_TTL)
      ChannelBot.seat_bots(channel, spec[:bots])
      ChannelBot.welcome!(channel)
      channel
    end
  rescue ActiveRecord::RecordNotUnique
    # Two visitors opened the same fresh city channel at once — (slug, city) is
    # unique, so the loser adopts the winner's row.
    includes(:city).find_by!(slug: slug, city_id: city&.id)
  end

  # Anonymous, radius-scoped group room — same public/anonymous/disappearing
  # machinery as CHANNELS above, but bucketed by a ~10km geo grid cell instead
  # of by city. Soft guests and signed-in users both join (NearbyController
  # stores lat/lng on Current.user after the browser grants geolocation).
  # Not seeded with bots — meant to read as people actually nearby, not an
  # always-on lobby. Empty cells are normal; the city #brgen channel is the
  # no-GPS anonymous chat fallback.
  GEO_ROOM_RADIUS_KM = 10.0
  GEO_ROOM_SLUG_PREFIX = "nearby-"

  def self.geo_room_slug?(slug) = slug.to_s.start_with?(GEO_ROOM_SLUG_PREFIX)

  def self.find_or_create_geo_room(lat:, lng:)
    slug = "#{GEO_ROOM_SLUG_PREFIX}#{Shared::GeoLocatable.cell_id(lat: lat, lng: lng, km: GEO_ROOM_RADIUS_KM)}"
    # city_id is always nil — scope without tenant so a city tenant cannot hide
    # an existing cross-city cell room.
    ActsAsTenant.without_tenant do
      find_by(slug: slug, city_id: nil) || create_geo_room!(slug)
    end
  end

  def self.create_geo_room!(slug)
    create!(conversation_type: "group", slug: slug, city_id: nil, name: "Nearby chat", disappearing_duration: CHANNEL_TTL)
  rescue ActiveRecord::RecordNotUnique
    # Two nearby visitors opened a fresh room in the same cell at once.
    ActsAsTenant.without_tenant { find_by!(slug: slug, city_id: nil) }
  end

  # "#takeaway · Bergen" once a room is city-scoped; plain "#takeaway" otherwise.
  def channel_title = city ? "#{name} · #{city.name}" : name

  def channel? = slug.present?

  # A cheap "is this room alive right now" signal: distinct voices (people +
  # bots) that spoke in the last 20 minutes. Not real-time presence — it
  # refreshes on load, but it's enough to steer people toward a live room.
  ACTIVE_WINDOW_SECONDS = 20 * 60

  def recent_active_count
    messages.where(created_at: (Time.current - ACTIVE_WINDOW_SECONDS)..).distinct.count(:sender_id)
  end

  # find_or_create_by! is a read then a write, and two joins of the same room
  # interleave between the halves. The unique index added in
  # 20260825120000 is what actually stops the second write; this rescue is how
  # the loser of that race gets the winner's row instead of a 500. Without both,
  # a duplicate row split `last_read_at` and the unread badge never cleared.
  def join!(user, role: "member")
    membership = begin
      conversation_participants.find_or_create_by!(user_id: user.id)
    rescue ActiveRecord::RecordNotUnique
      conversation_participants.find_by!(user_id: user.id)
    end
    # Only ever raise a role (member -> voice -> op); a bot re-seated or a human
    # re-opening the room never loses its mode.
    if ConversationParticipant::RANK.fetch(role, 0) > ConversationParticipant::RANK.fetch(membership.role, 0)
      membership.update!(role: role)
    end
    membership
  end

  # The messenger list, in one SQL order: the viewer's pins first, newest pin
  # above older ones, then everything else by its last message. Ordering in Ruby
  # after the fact would pin nothing on page two, because the page is chosen
  # before the sort. Reads the joined participant row that `for_user` already
  # filters to the viewer, so it is their pins and nobody else's.
  INBOX_ORDER = Arel.sql(
    "CASE WHEN conversation_participants.pinned_at IS NULL THEN 1 ELSE 0 END, " \
    "conversation_participants.pinned_at DESC, " \
    "COALESCE((SELECT MAX(m.created_at) FROM messages m " \
    "WHERE m.conversation_id = conversations.id), conversations.created_at) DESC"
  )

  # Two subqueries, not two calls to for_user. `for_user(a).for_user(b)` reads
  # as an intersection and is not one: both scopes join the SAME association, so
  # Rails collapses them into one join and ANDs the predicates on it —
  # `user_id = a AND user_id = b` on a single row, which no row satisfies. This
  # method therefore always answered nil, find_or_create_direct always created,
  # and every pair of people got a fresh thread each time they opened a DM from
  # a different button, splitting their history across duplicates.
  def self.direct_between(a, b)
    where(conversation_type: "direct")
      .where(id: ConversationParticipant.where(user_id: a.id).select(:conversation_id))
      .where(id: ConversationParticipant.where(user_id: b.id).select(:conversation_id))
      .order(:id).first
  end

  def self.find_or_create_direct(a, b)
    direct_between(a, b) || create!(conversation_type: "direct").tap do |c|
      c.participants << a << b
    end
  end

  # A group DM: a named conversation with more than two people in it, as opposed
  # to a #channel, which is a public room with a slug. Both are
  # conversation_type "group"; slug is what tells them apart, and every DM
  # surface already filters on `slug: nil`.
  MAX_GROUP_PARTICIPANTS = 50

  def self.create_group!(creator:, name:, users: [])
    transaction do
      group = create!(conversation_type: "group", name: name.to_s.strip.presence, city: Current.city_record)
      # The creator is an op. Nothing else in the app appoints one, so a group
      # created without an op could never be renamed or moderated by anyone.
      group.join!(creator, role: "op")
      users.uniq.excluding(creator).each { |user| group.join!(user) }
      group
    end
  end

  def group_dm? = conversation_type == "group" && slug.blank?

  # Ops rename the room and remove people; any member may add. A group chat
  # where only the founder can bring a friend in is one people work around by
  # starting a second group.
  def admin?(user)
    return false if user.blank?

    conversation_participants.exists?(user_id: user.id, role: "op")
  end

  # A group without an op can never be renamed or moderated again, so the last
  # one leaving hands the room to whoever has been in it longest rather than
  # being refused — refusing would trap someone in a chat they want to leave.
  def promote_longest_standing!
    return if conversation_participants.exists?(role: "op")

    conversation_participants.order(:created_at, :id).first&.update!(role: "op")
  end

  def unread_count_for(user)
    participant = conversation_participants.find_by(user:)
    return 0 unless participant
    messages.where("created_at > ?", participant.last_read_at || Time.at(0)).count
  end

  # unread_count_for is two queries (find_by participant, then COUNT) and is the
  # right shape for one record. It is the wrong shape for a list, and both callers
  # were lists: the messenger index ran it per row, and the layout summed it across
  # every DM on EVERY authenticated render of EVERY page, purely to decide a badge
  # number — 2 queries per thread added to each pageview, on a 1GB box.
  #
  # Same predicate, expressed once in SQL. The JOIN fans a message out per
  # participant and the user_id filter collapses it back, so each message is
  # counted once. COALESCE mirrors the `|| Time.at(0)` above: a participant who has
  # never opened the thread has everything unread.
  def self.unread_scope_for(user)
    Message.joins(conversation: :conversation_participants)
           .where(conversation_participants: { user_id: user.id })
           .where(
             "messages.created_at > COALESCE(conversation_participants.last_read_at, ?)",
             Time.at(0)
           )
  end

  # DMs only — public channels are ambient and must not light the badge.
  def self.unread_total_for(user)
    unread_scope_for(user).where(conversations: { slug: nil }).count
  end

  # { conversation_id => unread count }, for rendering a list of threads.
  # Absent key means zero, so callers should fetch with a 0 default.
# Message and active-speaker counts for a set of rooms, in one query each.
#
# channels#index rendered seven rooms and asked each one for recent_active_count
# and then messages.size — two COUNTs per room, fourteen queries to draw a list
# of seven links. Same shape as unread_counts_for above, and the same fix.
def self.message_counts_for(conversations)
  Message.where(conversation_id: conversations).group(:conversation_id).count
end

def self.active_counts_for(conversations)
  Message.where(conversation_id: conversations)
         .where(created_at: (Time.current - ACTIVE_WINDOW_SECONDS)..)
         .group(:conversation_id)
         .distinct
         .count(:sender_id)
end

  def self.unread_counts_for(user)
    unread_scope_for(user).group("messages.conversation_id").count
  end

  # Three queries, not two per message.
  #
  # This walked every unexpired message with find_each and did a find_or_initialize
  # plus an update! on each one — a SELECT and often an INSERT per message, every
  # time somebody opened a room. A channel holding a hundred messages cost two
  # hundred round trips to render, on the read path, on one vCPU.
  #
  # The semantics are the same and worth stating, because the obvious rewrite gets
  # them wrong: read_at is only ever set when it was blank. When a message was
  # first read is a fact, and an upsert that overwrites it would quietly turn every
  # revisit into a new "first read".
  def mark_read_for!(user)
    conversation_participants.find_by(user:)&.update!(last_read_at: Time.current)

    ids = messages.unexpired.pluck(:id)
    return if ids.empty?

    now = Time.current
    seen = MessageReceipt.where(message_id: ids, user_id: user.id).pluck(:message_id, :read_at)
    already = seen.to_h

    missing = ids - already.keys
    if missing.any?
      MessageReceipt.insert_all(
        missing.map { |mid| { message_id: mid, user_id: user.id, read_at: now, created_at: now, updated_at: now } },
      )
    end

    unread = already.filter_map { |mid, read_at| mid if read_at.nil? }
    return if unread.empty?

    MessageReceipt.where(message_id: unread, user_id: user.id).update_all(read_at: now, updated_at: now)
  end

  DISAPPEARING_OPTIONS = {
    "off" => nil,
    "1m" => 60,
    "5m" => 300,
    "1h" => 3600,
    "24h" => 86_400
  }.freeze

  def disappearing_messages? = disappearing_duration.present? && disappearing_duration.positive?

  def display_name_for(user)
    return name if conversation_type == "group" && name.present?

    other_participants(user).first&.display_name || "Unknown"
  end

# reject when the association is already loaded, where.not when it is not.
#
# Every caller of display_name_for renders a list — the inbox, the rooms rail,
# the forward-target picker — and every one of those controllers preloads
# :participants. A `where` on an association ignores that and issues its own
# SELECT, so the preload was bought and then bypassed once per row. Adding the
# rail made it two lists per page and the query budget caught it; the defect was
# already there in the inbox.
#
# Same family as message_receipts.find_by and outfit.items.count: `where`,
# `find_by` and `count` all go to the database whatever is in memory, while
# `reject`, `detect` and `size` read what is there.
def other_participants(user)
  return participants.reject { |p| p.id == user.id } if participants.loaded?

  participants.where.not(id: user.id)
end
end
