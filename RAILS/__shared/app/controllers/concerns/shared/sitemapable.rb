# frozen_string_literal: true

module Shared
  # Include in a SitemapsController and implement #sitemap_entries to return
  # an array of Shared::SitemapBuilder::Entry — the XML rendering is shared.
  module Sitemapable
    extend ActiveSupport::Concern

    def index
      render xml: Shared::SitemapBuilder.render(sitemap_entries)
    end
  end
end
