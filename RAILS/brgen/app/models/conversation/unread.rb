# frozen_string_literal: true

class Conversation
  # What a participant has not read yet, for one thread, for a list of threads,
  # and the write that marks a room read.
  module Unread
    extend ActiveSupport::Concern

    class_methods do
      # unread_count_for is two queries (find_by participant, then COUNT) and is the
      # right shape for one record. It is the wrong shape for a list, and both callers
      # were lists: the messenger index ran it per row, and the layout summed it across
      # every DM on EVERY authenticated render of EVERY page, purely to decide a badge
      # number — 2 queries per thread added to each pageview, on a 1GB box.
      #
      # Same predicate, expressed once in SQL. The JOIN fans a message out per
      # participant and the user_id filter collapses it back, so each message is
      # counted once. COALESCE mirrors the `|| Time.at(0)` in unread_count_for: a
      # participant who has never opened the thread has everything unread.
      def unread_scope_for(user)
        Message.joins(conversation: :conversation_participants)
               .where(conversation_participants: { user_id: user.id })
               .where(
                 "messages.created_at > COALESCE(conversation_participants.last_read_at, ?)",
                 Time.at(0)
               )
      end

      # DMs only — public channels are ambient and must not light the badge.
      def unread_total_for(user)
        unread_scope_for(user).where(conversations: { slug: nil }).count
      end

      # The newest message of each conversation, in two queries. A list row shows
      # one preview line, and includes(:messages) loaded every message of every
      # thread on the page to supply it.
      def last_messages_for(conversations)
        newest = Message.where(conversation_id: conversations).group(:conversation_id).select("MAX(messages.id)")
        Message.where(id: newest).index_by(&:conversation_id)
      end

      # { conversation_id => unread count }, for rendering a list of threads.
      # Absent key means zero, so callers should fetch with a 0 default.
      def unread_counts_for(user)
        unread_scope_for(user).group("messages.conversation_id").count
      end
    end

    def unread_count_for(user)
      participant = conversation_participants.find_by(user:)
      return 0 unless participant
      messages.where("created_at > ?", participant.last_read_at || Time.at(0)).count
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
  end
end
