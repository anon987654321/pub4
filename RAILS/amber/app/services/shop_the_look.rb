# frozen_string_literal: true

# Commerce suggestions are ordered from the user's own saved links first, then
# explainable BRGEN local listings, then optional TradeDoubler inventory.
#
# BRGEN is the transaction owner. Amber only answers the wardrobe question:
# "does this market item make sense here?" It never copies the marketplace DB.
module ShopTheLook
  Suggestion = Data.define(:title, :merchant, :url, :source, :score, :reasons, :commerce_key)

  class << self
    def for_item(item, limit: 6)
      (local_links(item) + remote_suggestions(item, limit: limit))
        .uniq(&:url)
        .sort_by { |suggestion| [ -suggestion.score, suggestion.source == "saved" ? 0 : 1 ] }
        .first(limit)
    end

    def local_links(item)
      epi = Shared::LinkConverter.epi_for(surface: "amber", post_id: item.id)

      Array(item.affiliate_links).map do |link|
        link_metadata = link.metadata.is_a?(Hash) ? link.metadata : {}
        Suggestion.new(
          link_metadata["title"].to_s.presence || item.title.to_s,
          link.merchant.to_s,
          Shared::LinkConverter.wrap(link.url.to_s, epi: epi),
          "saved",
          1.0,
          [ I18n.t("commerce_fit.saved", default: "Saved by you.") ],
          link_metadata["commerce_key"].to_s.presence
        )
      end
    end

    def remote_unavailable_reason(item = nil)
      return :no_query if item && query_for(item).blank?
      return nil if BrgenCommerce.available?
      return nil if tradedoubler_configured?

      :no_market_sources
    end

    def remote_available?
      remote_unavailable_reason.nil?
    end

    def query_for(item)
      [ item.brand, item.title, item.category, item.color, item.material ].compact.join(" ").strip
    end

    def remote_suggestions(item, limit:)
      query = query_for(item)
      return [] if query.blank?

      suggestions = brgen_suggestions(item, limit: limit)
      suggestions.concat(tradedoubler_suggestions(item, limit: limit)) if tradedoubler_available?
      suggestions.sort_by { |suggestion| -suggestion.score }.first(limit)
    rescue StandardError => e
      Rails.logger.warn("shop_the_look scoring failed: #{e.class}: #{e.message}")
      []
    end

    def brgen_suggestions(item, limit:)
      BrgenCommerce.search(item:, limit: [ limit * 2, 12 ].min).filter_map do |product|
        fit = CommerceFit.evaluate(item, product)
        next if fit.score < 0.20

        Suggestion.new(
          product.title,
          product.merchant,
          product.url,
          "brgen",
          fit.score,
          (fit.reasons + product.reasons).first(3),
          product.id
        )
      end
    rescue StandardError => e
      Rails.logger.warn("brgen commerce scoring failed: #{e.class}: #{e.message}")
      []
    end

    def tradedoubler_available?
      tradedoubler_configured? &&
        defined?(Shared::Tradedoubler) &&
        Shared::Tradedoubler.respond_to?(:deals)
    end

    def tradedoubler_configured?
      ENV["TRADEDOUBLER_TOKEN"].present? || ENV["TRADEDOUBLER_PRODUCTS_TOKEN"].present?
    end

    def tradedoubler_suggestions(item, limit:)
      query = query_for(item)

      Shared::Tradedoubler.deals(limit: limit).filter_map do |deal|
        next if deal.placeholder

        score = text_score(query, "#{deal.title} #{deal.merchant}")
        next if score < 0.15

        Suggestion.new(
          deal.title,
          deal.merchant,
          deal.click_url,
          "tradedoubler",
          score,
          [ I18n.t("commerce_fit.feed_match", default: "Matches the available product feed.") ],
          nil
        )
      end
    end

    def text_score(query, candidate)
      words = query.downcase.split(/\W+/).reject { |word| word.length < 3 }.uniq
      return 0.0 if words.empty?

      candidate_text = candidate.downcase
      (words.count { |word| candidate_text.include?(word) }.to_f / words.length).clamp(0.0, 1.0)
    end
  end
end
