# frozen_string_literal: true

# Suggest similar commerce links for a wardrobe item from brand/title text.
#
# Amber does not import TradeDoubler feeds itself (that lives on brgen). This
# service ranks existing AffiliateLink rows on the item and, when
# TRADEDOUBLER_TOKEN is present and a lightweight search helper is available,
# returns remote suggestion hashes the UI can offer as one-click affiliate links.
module ShopTheLook
  Suggestion = Data.define(:title, :merchant, :url, :source, :score)

  class << self
    def for_item(item, limit: 6)
      local = local_links(item)
      remote = remote_suggestions(item, limit: limit)
      (local + remote).uniq { |s| s.url }.first(limit)
    end

    def local_links(item)
      Array(item.affiliate_links).map do |link|
        Suggestion.new(
          title: item.title.to_s,
          merchant: link.merchant.to_s,
          url: link.url.to_s,
          source: "saved",
          score: 1.0
        )
      end
    end

    def remote_suggestions(item, limit:)
      return [] unless ENV["TRADEDOUBLER_TOKEN"].present? || ENV["TRADEDOUBLER_PRODUCTS_TOKEN"].present?

      query = [item.brand, item.title, item.category].compact.join(" ").strip
      return [] if query.blank?

      # Amber stays self-contained: optional HTTP search against brgen public
      # deals is out of scope. Operators can paste TD links; when a local
      # Tradedoubler constant exists (shared deploy), use it.
      return [] unless defined?(Tradedoubler) && Tradedoubler.respond_to?(:deals)

      Tradedoubler.deals(limit: limit).filter_map do |deal|
        next if deal.placeholder

        score = text_score(query, "#{deal.title} #{deal.merchant}")
        next if score < 0.15

        Suggestion.new(
          title: deal.title,
          merchant: deal.merchant,
          url: deal.click_url,
          source: "tradedoubler",
          score: score
        )
      end.sort_by { |s| -s.score }.first(limit)
    rescue StandardError
      []
    end

    def text_score(query, candidate)
      q = query.downcase.split(/\W+/).reject { |w| w.length < 3 }
      return 0.0 if q.empty?

      c = candidate.downcase
      hits = q.count { |w| c.include?(w) }
      hits.to_f / q.size
    end
  end
end
