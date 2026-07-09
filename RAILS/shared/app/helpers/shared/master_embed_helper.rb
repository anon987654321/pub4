# frozen_string_literal: true

module Shared
  module MasterEmbedHelper
    def master_web_url = Rails.application.config.x.master_web_url

    def master_embed_title
      @master_embed_title.presence || "AI"
    end
  end
end