# frozen_string_literal: true

module Shared
  # Asks the provider about a record's pending or stale link and stores the answer,
  # which is either a player facade or, when the provider will not describe
  # the link, a failure that leaves the plain link showing.
  class LinkEmbedJob < ApplicationJob
    queue_as :bulk

    def perform(record)
      stored = record.link_embed_record
      return unless stored && (stored.pending? || stored.stale?)

      # The text may have changed since this was enqueued, and the save that
      # changed it enqueued its own job.
      current = Shared::LinkEmbed.find(record[record.link_embed_source])
      return unless current && current.source_url == stored.match.source_url

      # updated_at with it: feed cards are fragment-cached on the post, and a
      # write that leaves updated_at alone leaves every cached card without its
      # player.
      record.update_columns(link_embed: answer(stored, current).to_h, updated_at: Time.current)
      # update_columns runs no callback, so a record that shows the player live
      # (brgen Post) is told here.
      record.try(:link_embed_resolved)
    end

    private

    # A refresh that fails keeps the player it had; only the time moves on, so
    # the next try is a month away rather than tomorrow.
    def answer(stored, current)
      fresh = Shared::LinkEmbed.resolve(current)
      stored.ok? && !fresh.ok? ? stored.with(fetched_at: Time.current.utc.iso8601) : fresh
    end
  end
end
