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

    # Saved links, attributed.
    #
    # This emitted `link.url` verbatim, which is the second reason amber earned
    # nothing: with no website id in the URL a converting click pays nobody, so
    # the whole "shop the look" surface was a link list. Shared::LinkConverter
    # returns the URL unchanged when TRADEDOUBLER_WEBSITE_ID is unset (an
    # unattributed link still works, and inventing tracking is what
    # affiliate_honesty forbids) and when the owner already pasted a tracked URL.
    #
    # Server-side as well as through the Link Converter script, because the script
    # is exactly what an ad blocker removes and this path does not depend on JS.
    def local_links(item)
      epi = Shared::LinkConverter.epi_for(surface: "amber", post_id: item.id)

      Array(item.affiliate_links).map do |link|
        Suggestion.new(
          title: item.title.to_s,
          merchant: link.merchant.to_s,
          url: Shared::LinkConverter.wrap(link.url.to_s, epi: epi),
          source: "saved",
          score: 1.0
        )
      end
    end

    # Why the remote feed cannot answer, or nil when it can.
    #
    # This used to be two silent `return []` guards, and the second one was
    # unconditional in amber: the feed client lived in brgen's app/services and
    # was never loaded in this process, so setting TRADEDOUBLER_TOKEN in
    # /etc/amber.env passed the first gate, hit the second, and produced nothing
    # — configuration with no reader, reporting nothing. Naming the reason is
    # what made that visible instead of empty.
    #
    # It is `Shared::Tradedoubler` now and amber loads it, so a token set here
    # reaches a client that can answer. The guard stays because the reasons are
    # still distinct and still worth telling apart: no token, no client, no
    # query. It is no longer the one that is always true.
    def remote_unavailable_reason(item = nil)
      return :no_token unless ENV["TRADEDOUBLER_TOKEN"].present? || ENV["TRADEDOUBLER_PRODUCTS_TOKEN"].present?
      return :no_feed_client unless defined?(Shared::Tradedoubler) && Shared::Tradedoubler.respond_to?(:deals)
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

      Shared::Tradedoubler.deals(limit: limit).filter_map do |deal|
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
