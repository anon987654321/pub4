# frozen_string_literal: true

class Conversation
  # Public IRC-style rooms: one per vertical plus a city-wide lobby, each a group
  # Conversation found by its stable slug, and the counts that draw their list.
  module Channels
    extend ActiveSupport::Concern

    # `bots` names the personas (see ChannelBot::PERSONAS) that hang out there.
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

    # A cheap "is this room alive right now" signal: distinct voices (people +
    # bots) that spoke in the last 20 minutes. Not real-time presence — it
    # refreshes on load, but it's enough to steer people toward a live room.
    ACTIVE_WINDOW_SECONDS = 20 * 60

    class_methods do
      def channel_slug?(slug) = CHANNELS.key?(slug.to_s)

      # The room's one-line description, in the reader's language.
      #
      # `blurb:` above stays as the English source string and as the fallback, but
      # nothing user-facing may read it directly: the channels index, the room
      # header, the IRC topic and ChannelBot's welcome line all render to visitors
      # of a Norwegian site, and all four printed the constant.
      def channel_blurb(slug)
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
      def find_or_create_channel(slug, city: nil)
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
      def rewelcome_if_empty!(channel)
        return unless channel.channel?
        return if channel.messages.unexpired.exists?

        ChannelBot.welcome!(channel)
      rescue StandardError => e
        # Opening a room must not 500 because the greeting failed. Surfaced rather
        # than swallowed: a silent rescue here would hide the same emptiness this
        # method exists to fix.
        Rails.logger.warn("conversation:rewelcome_failed slug=#{channel.slug} #{e.class}: #{e.message}")
      end

      def create_channel!(slug, spec, city)
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

      # Message and active-speaker counts for a set of rooms, in one query each.
      #
      # channels#index rendered seven rooms and asked each one for recent_active_count
      # and then messages.size — two COUNTs per room, fourteen queries to draw a list
      # of seven links. Same shape as unread_counts_for, and the same fix.
      def message_counts_for(conversations)
        Message.where(conversation_id: conversations).group(:conversation_id).count
      end

      def active_counts_for(conversations)
        Message.where(conversation_id: conversations)
               .where(created_at: (Time.current - ACTIVE_WINDOW_SECONDS)..)
               .group(:conversation_id)
               .distinct
               .count(:sender_id)
      end
    end

    # "#takeaway · Bergen" once a room is city-scoped; plain "#takeaway" otherwise.
    def channel_title = city ? "#{name} · #{city.name}" : name

    def channel? = slug.present?

    def recent_active_count
      messages.where(created_at: (Time.current - ACTIVE_WINDOW_SECONDS)..).distinct.count(:sender_id)
    end
  end
end
