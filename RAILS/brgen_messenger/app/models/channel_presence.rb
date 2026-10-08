# frozen_string_literal: true

# Who has this room open right now.
#
# Conversation#recent_active_count answers a different question -- distinct
# voices that *spoke* in the last 20 minutes -- and says so in its own comment.
# A reader sitting in a quiet room is present but silent, and someone who posted
# 19 minutes ago and closed the tab is absent but counted. Discord's "who's
# here" is about open windows, so it needs a heartbeat.
#
# Cache-backed rather than a table on purpose: presence is soft, expiring,
# high-write data that nobody needs to query historically, and a per-beat INSERT
# on SQLite for every reader in every open room is the wrong trade. It also keeps
# this deployable without a migration.
#
# Requires a SHARED cache store to be correct. Production runs Solid Cache, which
# is shared across Falcon processes, so the count is whole. Development's
# MemoryStore is per-process: with one Puma process that is still right, but a
# clustered dev server would report each worker's own readers. If presence ever
# looks low, check the store before the logic.
#
# One key per conversation holding {user_id => expires_at}, read-modify-write.
# That races under concurrent beats and the loser is a dropped heartbeat, which
# self-corrects on the next one 20s later -- acceptable for a count that is
# already approximate. A per-user key would avoid the race but cannot be counted:
# Solid Cache has no key enumeration.
class ChannelPresence
  TTL = 45 # seconds; must exceed the client's beat interval with room to spare
  BEAT = 20

  class << self
    def touch!(conversation:, user:)
      return 0 unless conversation && user

      before = ids_for(conversation)
      live = prune(read(conversation)).merge(user.id => Time.current.to_i + TTL)
      write(conversation, live)

      broadcast(conversation) if live.keys.sort != before
      live.size
    end

    def leave!(conversation:, user:)
      return unless conversation && user

      live = prune(read(conversation))
      next_live = live.except(user.id)
      return if next_live.keys.sort == live.keys.sort

      write(conversation, next_live)
      broadcast(conversation)
    end

    def count_for(conversation) = ids_for(conversation).size

    def ids_for(conversation)
      return [] unless conversation

      prune(read(conversation)).keys.sort
    end

    private

    def key(conversation) = "brgen:presence:conversation:#{conversation.id}"

    def read(conversation)
      value = Rails.cache.read(key(conversation))
      value.is_a?(Hash) ? value : {}
    rescue StandardError => e
      # A presence count is never worth failing a request over — but the
      # failure is still logged (FAIL_VISIBLY): tolerated is not invisible.
      Rails.logger.debug { "channel_presence read failed: #{e.class}: #{e.message}" }
      {}
    end

    def write(conversation, live)
      Rails.cache.write(key(conversation), live, expires_in: (TTL * 2).seconds)
    rescue StandardError => e
      Rails.logger.warn("channel_presence write failed: #{e.class}: #{e.message}")
      nil
    end

    def prune(live)
      now = Time.current.to_i
      live.select { |_id, expires_at| expires_at.to_i > now }
    end

    def broadcast(conversation)
      Turbo::StreamsChannel.broadcast_replace_to(
        conversation,
        target: "presence_#{conversation.id}",
        partial: "conversations/presence",
        locals: { conversation: conversation }
      )
    rescue StandardError => e
      Rails.logger.warn("channel_presence broadcast failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
