# frozen_string_literal: true

module Shared
  # A record whose text may carry a media link, and the player that link
  # resolves to, kept in its `link_embed` JSON column.
  #
  # The link is found when the text is saved and resolved off the request by
  # Shared::LinkEmbedJob, so writing a post never waits on a provider. brgen
  # keeps a worker up; amber's queue drains within the hour, and until the job
  # runs the post shows the plain link.
  module LinkEmbeddable
    extend ActiveSupport::Concern

    included do
      class_attribute :link_embed_source, instance_writer: false
    end

    class_methods do
      def embeds_links_from(attribute)
        self.link_embed_source = attribute
        before_save :track_link_embed, if: -> { will_save_change_to_attribute?(attribute) }
        after_commit :resolve_link_embed_later, on: %i[create update], if: :link_embed_awaits_provider?
      end
    end

    def link_embed_record = Shared::LinkEmbed::Record.from_stored(link_embed)

    private

    # The same link keeps what was already resolved for it, a new link starts
    # pending, and text with no recognised link carries no embed.
    def track_link_embed
      found = Shared::LinkEmbed.find(self[link_embed_source])
      if found.nil?
        self.link_embed = nil
      elsif link_embed_record&.match&.source_url != found.source_url
        self.link_embed = Shared::LinkEmbed::Record.pending(found).to_h
      end
    end

    def link_embed_awaits_provider?
      saved_change_to_link_embed? && link_embed_record&.pending?
    end

    def resolve_link_embed_later = Shared::LinkEmbedJob.perform_later(self)
  end
end
