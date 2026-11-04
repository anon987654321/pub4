# frozen_string_literal: true

module Shared
  # Asks again about the links whose answer has gone stale (Record#stale?):
  # a failed lookup after a day, a resolved one after a month. Without it a
  # link the provider would not describe once stayed a plain link for good.
  # The apps' recurring.yml names the model that embeds links.
  class LinkEmbedRefreshJob < ApplicationJob
    queue_as :bulk

    # Lookups per run, so one sweep never floods a provider.
    BATCH = 200

    def perform(model_name)
      model = model_name.constantize
      embedded = model.where.not(link_embed: nil)
      queued = 0
      embedded.find_each do |record|
        next unless record.link_embed_record&.stale?

        Shared::LinkEmbedJob.perform_later(record)
        break if (queued += 1) >= BATCH
      end
    end
  end
end
