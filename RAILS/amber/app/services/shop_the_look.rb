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

    # Why the remote feed cannot answer, or nil when it can.
    #
    # This used to be two silent `return []` guards, and the second one is
    # unconditional in amber: `Tradedoubler` is defined in brgen's app/services
    # and is never loaded in this process. So setting TRADEDOUBLER_TOKEN in
    # /etc/amber.env passed the first gate, hit the second, and produced
    # nothing — configuration with no reader, reporting nothing. Name the
    # reason so the UI can say which of the two it is.
    def remote_unavailable_reason(item = nil)
      return :no_token unless ENV["TRADEDOUBLER_TOKEN"].present? || ENV["TRADEDOUBLER_PRODUCTS_TOKEN"].present?
      return :no_feed_client unless defined?(Tradedoubler) && Tradedoubler.respond_to?(:deals)
      return :no_query if item && query_for(item).blank?

      nil
    end

    def remote_available? = remote_unavailable_reason.nil?

    def query_for(item)
      [ item.brand, item.title, item.category ].compact.join(" ").strip
    end

    def remote_suggestions(item, limit:)
      return [] if remote_unavailable_reason(item)

      query = query_for(item)

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
