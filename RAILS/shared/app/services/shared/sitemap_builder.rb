# frozen_string_literal: true

module Shared
  # Renders a sitemaps.org urlset from plain entries — one XML builder shared
  # by every app instead of each hand-rolling its own escaping/formatting.
  class SitemapBuilder
    Entry = Data.define(:loc, :lastmod, :changefreq, :priority) do
      def initialize(loc:, lastmod: nil, changefreq: nil, priority: nil)
        super
      end
    end

    def self.render(entries)
      new(entries).render
    end

    def initialize(entries)
      @entries = entries
    end

    def render
      xml = Builder::XmlMarkup.new(indent: 2)
      xml.instruct!
      xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
        @entries.each do |entry|
          xml.url do
            xml.loc entry.loc
            xml.lastmod entry.lastmod.iso8601 if entry.lastmod
            xml.changefreq entry.changefreq if entry.changefreq
            xml.priority entry.priority if entry.priority
          end
        end
      end
      xml.target!
    end
  end
end
