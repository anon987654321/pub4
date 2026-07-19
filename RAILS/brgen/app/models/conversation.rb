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
    "brgen"       => { name: "#brgen",       vertical: nil,           blurb: "The city-wide lobby — anything goes.",              bots: %w[master echo] },
    "marketplace" => { name: "#marketplace", vertical: "marketplace", blurb: "Buying, selling, haggling, and finds.",              bots: %w[curator echo] },
    "dating"      => { name: "#dating",      vertical: "dating",      blurb: "Flirt, vent, and swap first-date ideas.",           bots: %w[cupid echo] },
    "playlist"    => { name: "#playlist",    vertical: "playlist",    blurb: "Now playing — share tracks and listening parties.", bots: %w[dj echo] },
    "tv"          => { name: "#tv",          vertical: "tv",          blurb: "Live threads for shows and streams.",               bots: %w[critic echo] },
    "takeaway"    => { name: "#takeaway",    vertical: "takeaway",    blurb: "What's good to order right now?",                   bots: %w[foodie echo] },
    "maps"        => { name: "#maps",        vertical: "maps",        blurb: "Local spots, tips, and directions.",                bots: %w[scout echo] }
  }.freeze

  # Channels are ephemeral: messages fade so a room reads as "what's happening
  # now" rather than an endless scrollback. Reuses the disappearing-message
  # machinery (Message#schedule_expiration + MessageExpirationJob).
  CHANNEL_TTL = ENV.fetch("BRGEN_CHANNEL_TTL_SECONDS", (6 * 3600).to_s).to_i

  def self.channel_slug?(slug) = CHANNELS.key?(slug.to_s)

  # Idempotently resolve a channel by slug, seeding its bots + a welcome line
  # the first time it is opened.
  def self.find_or_create_channel(slug, city: nil)
    slug = slug.to_s
    spec = CHANNELS[slug] or return nil
    find_by(slug: slug, city_id: city&.id) || create_channel!(slug, spec, city)
  end

  def self.create_channel!(slug, spec, city)
    transaction do
      channel = create!(conversation_type: "group", slug: slug, city_id: city&.id,
                        name: spec[:name], vertical: spec[:vertical], disappearing_duration: CHANNEL_TTL)
      ChannelBot.seat_bots(channel, spec[:bots])
      ChannelBot.welcome!(channel)
      channel
    end
  rescue ActiveRecord::RecordNotUnique
    # Two visitors opened the same fresh city channel at once — (slug, city) is
    # unique, so the loser just adopts the winner's row.
    find_by!(slug: slug, city_id: city&.id)
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

  def join!(user)
    return if participants.exists?(user.id)

    participants << user
  end

  def self.direct_between(a, b)
    for_user(a).for_user(b).where(conversation_type: "direct").first
  end

  def self.find_or_create_direct(a, b)
    direct_between(a, b) || create!(conversation_type: "direct").tap do |c|
      c.participants << a << b
    end
  end

  def unread_count_for(user)
    participant = conversation_participants.find_by(user:)
    return 0 unless participant
    messages.where("created_at > ?", participant.last_read_at || Time.at(0)).count
  end

  def mark_read_for!(user)
    conversation_participants.find_by(user:)&.update!(last_read_at: Time.now)
    messages.unexpired.find_each do |message|
      receipt = message.message_receipts.find_or_initialize_by(user: user)
      receipt.update!(read_at: Time.current) unless receipt.read_at
    end
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

  def other_participants(user)
    participants.where.not(id: user.id)
  end
end
