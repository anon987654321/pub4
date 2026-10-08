# frozen_string_literal: true

require "uri"

module Shared
  module MasterEmbedHelper
    # Base MASTER face URL. Pass autostart:/embed: true so the face skips the
    # "launch AI" primer and boots without a second click (embeds + front-page
    # entrypoints). Full-page visits to ai.brgen.no keep the primer for consent.
    def master_web_url(autostart: false, embed: false)
      base = Rails.application.config.x.master_web_url.to_s
      return base unless autostart || embed

      uri = URI.parse(base)
      q = URI.decode_www_form(String(uri.query))
      q << %w[autostart 1] if autostart
      q << %w[embed 1] if embed
      uri.query = URI.encode_www_form(q)
      uri.to_s
    rescue URI::InvalidURIError
      base
    end

    def master_embed_title
      @master_embed_title.presence ||
        (respond_to?(:t) ? t("master.embed_heading", default: t("master.title", default: "AI")) : "AI")
    end
  end
end
