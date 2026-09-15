# frozen_string_literal: true

module Shared
  module LinkEmbed
    # What a post stores about the link it embeds, in a shape a view can trust.
    #
    # pending: the link is known and nobody has asked the provider yet.
    # ok:      the provider described it, so the post shows a player facade.
    # failed:  the provider would not, so the post shows the plain link.
    #
    # A stored row is read back through the same matcher that wrote it, so a
    # hand-edited or corrupted row cannot aim the player past the allowlist, and
    # an ok record without a title is not an ok record.
    Record = Data.define(:match, :status, :title, :author_name, :thumbnail_url, :fetched_at) do
      def self.pending(match) = new(match:, status: "pending")

      def self.from_oembed(match, oembed, at:)
        oembed = {} unless oembed.is_a?(Hash)
        new(match:, status: "ok", title: oembed["title"], author_name: oembed["author_name"],
            thumbnail_url: oembed["thumbnail_url"], fetched_at: at.utc.iso8601)
      end

      def self.from_stored(stored)
        return unless stored.is_a?(Hash)

        match = LinkEmbed.match_url(stored["source_url"].to_s)
        return unless match && match.provider.key == stored["provider"]
        return unless Record::STATUSES.include?(stored["status"])

        new(match:, status: stored["status"], title: stored["title"], author_name: stored["author_name"],
            thumbnail_url: stored["thumbnail_url"], fetched_at: stored["fetched_at"])
      end

      def initialize(match:, status:, title: nil, author_name: nil, thumbnail_url: nil, fetched_at: nil)
        title = Record.text(title, Record::TITLE_MAX)
        author_name = Record.text(author_name, Record::AUTHOR_MAX)
        thumbnail_url = nil unless match.provider.thumbnail?(thumbnail_url)
        status = "failed" if status == "ok" && title.nil?
        super
      end

      def self.text(value, max)
        return unless value.is_a?(String)

        cleaned = value.gsub(/[[:cntrl:]]/, " ").strip[0, max]
        cleaned unless cleaned.empty?
      end

      def ok? = status == "ok"
      def pending? = status == "pending"
      def player_url = match.provider.player_url(match.media_id)

      def to_h
        {
          "provider" => match.provider.key, "media_id" => match.media_id,
          "source_url" => match.source_url, "canonical_url" => match.canonical_url,
          "status" => status, "title" => title, "author_name" => author_name,
          "thumbnail_url" => thumbnail_url, "fetched_at" => fetched_at
        }.compact
      end
    end

    Record::STATUSES = %w[pending ok failed].freeze
    Record::TITLE_MAX = 200
    Record::AUTHOR_MAX = 100
  end
end
