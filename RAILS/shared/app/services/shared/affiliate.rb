# frozen_string_literal: true

# One read path over every affiliate network, so a new network is an adapter
# plus a line in NETWORKS rather than an edit to every view that shows a deal.
#
# Before this, `shared/_affiliate_deals` called Tradedoubler directly. That made
# TradeDoubler both "the network we happen to use" and "the way deals are read",
# so Amazon Associates could not appear on the surface at all without editing
# the view — and any second network would have had to be threaded through by
# hand everywhere.
#
# The table is the source of truth. Views read AffiliateProduct, which every
# importer writes into on its own schedule; a live call only happens as a
# last resort when the table has nothing, and even then it is cached. That
# ordering matters: an outbound HTTP call inside a page render turns an
# advertiser's outage into our latency.
module Shared
  module Affiliate
    # `placeholder` travels with the deal so the view can label it. Rendering
    # seeded placeholder inventory as an ordinary paid deal would be dishonest to
    # the visitor and unreconcilable against a payout report.
    Deal = Data.define(:title, :description, :price, :currency, :image_url, :click_url, :merchant, :placeholder)

    # Order is display priority when several networks can fill the same slot.
    # Named, not referenced: holding the classes here would make this file load
    # its adapters, and an adapter that wants Affiliate::Deal would then load
    # this file back. Zeitwerk resolves the names at call time instead.
    NETWORK_NAMES = %w[Tradedoubler AmazonAssociates].freeze

    class << self
      # Resolved inside Shared. Bare "Tradedoubler" would look for a top-level
      # constant that no longer exists, safe_constantize returns nil for it, and
      # filter_map drops it — so every network would go missing in silence and
      # configured_networks would simply report none.
      def networks = NETWORK_NAMES.filter_map { |name| "Shared::#{name}".safe_constantize }

      def configured_networks = networks.select(&:configured?)

      # Read path for views. Table first, across every source at once.
      def deals(category: nil, limit: 8)
        stored = stored_deals(category: category, limit: limit)
        return stored if stored.any?

        # Nothing stored: give each configured network one chance to answer, in
        # priority order, and stop at the first that does.
        configured_networks.each do |network|
          live = network.deals(category: category, limit: limit)
          return live if live.any?
        end

        []
      end

      def stored_deals(category: nil, limit: 8)
        return [] unless AffiliateProduct.table_exists?

        AffiliateProduct.sellable
                        .for_market(market)
                        .for_category(category)
                        .limit(limit)
                        .map { |product| to_deal(product) }
      rescue ActiveRecord::StatementInvalid
        # Pre-migration boot (deploy ordering) must not take the page down.
        []
      end

      # Write path. Every configured network imports; unconfigured ones report
      # zero rather than raising, so a partially-approved setup still works.
      def import_all!(category: nil)
        networks.to_h do |network|
          [ network.name.demodulize.underscore, network.configured? ? network.import!(category: category) : 0 ]
        end
      end

      def market = ENV.fetch("AFFILIATE_MARKET", ENV.fetch("TRADEDOUBLER_MARKET", "NO"))

      def to_deal(product)
        Deal.new(
          title: product.title.to_s,
          description: product.description.to_s.truncate(120),
          price: product.price.to_s,
          currency: product.currency.to_s,
          image_url: product.image_url.to_s,
          click_url: product.click_url.to_s,
          merchant: product.merchant.to_s,
          placeholder: product.placeholder
        )
      end
    end
  end
end
