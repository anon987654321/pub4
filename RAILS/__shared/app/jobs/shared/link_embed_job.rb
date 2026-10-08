# frozen_string_literal: true

module Shared
  # Asks the provider about a record's pending link and stores the answer,
  # which is either a player facade or, when the provider will not describe
  # the link, a failure that leaves the plain link showing.
  class LinkEmbedJob < ApplicationJob
    queue_as :bulk

    def perform(record)
      stored = record.link_embed_record
      return unless stored&.pending?

      # The text may have changed since this was enqueued, and the save that
      # changed it enqueued its own job.
      current = Shared::LinkEmbed.find(record[record.link_embed_source])
      return unless current && current.source_url == stored.match.source_url

      # updated_at with it: feed cards are fragment-cached on the post, and a
      # write that leaves updated_at alone leaves every cached card without its
      # player.
      record.update_columns(link_embed: Shared::LinkEmbed.resolve(current).to_h, updated_at: Time.current)
    end
  end
end
