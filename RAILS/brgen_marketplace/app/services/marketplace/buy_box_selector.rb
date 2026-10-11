# frozen_string_literal: true

module Marketplace
  class BuyBoxSelector
    WEIGHTS = {
      price: 0.35,
      delivery: 0.25,
      performance: 0.25,
      stock: 0.10,
      fulfilment: 0.05
    }.freeze

    FULFILMENT_SCORES = {
      0 => 0.25,
      1 => 1.0,
      2 => 0.8,
      3 => 0.55
    }.freeze

    Score = Data.define(:total, :price, :delivery, :performance, :stock, :fulfilment)
    Result = Data.define(:winner, :offers, :scores) do
      def score_for(listing) = scores[listing.id]

      def reasons_for(listing)
        return [] unless winner && listing && listing.id != winner.id

        reasons = []
        current = score_for(listing)
        winning = score_for(winner)
        return [] unless current && winning

        if listing.price_cents.to_i > winner.price_cents.to_i && winner.price_cents.to_i.positive?
          percent = ((listing.price_cents.to_f / winner.price_cents) - 1) * 100
          reasons << I18n.t("marketplace.buy_box_reason.price", percent: percent.round, default: "Your listed price is %{percent}% higher than the selected offer.")
        end
        if listing.delivery_promise.to_i > winner.delivery_promise.to_i
          reasons << I18n.t("marketplace.buy_box_reason.delivery",
                            current: delivery_label(listing), winner: delivery_label(winner), default: "Delivery is slower (%{current} versus %{winner}).")
        end
        if current.performance < winning.performance
          reasons << I18n.t("marketplace.buy_box_reason.performance",
                            score: (current.performance * 100).round, default: "Your seller-performance score is %{score}%.")
        end
        reasons << I18n.t("marketplace.buy_box_reason.combined", default: "The selected offer scores better across price, delivery, stock, fulfilment, and seller performance.") if reasons.empty?
        reasons
      end

      private

      def delivery_label(listing)
        key = Marketplace::Listing::DELIVERY_PROMISES.key(listing.delivery_promise)
        I18n.t("marketplace.delivery_promise.#{key}", default: listing.delivery_promise.to_s)
      end
    end

    def self.for(listing)
      return unless listing&.store_id.present? && listing.buy_box_key.present? && listing.city_id.present?

      offers = eligible_offers(listing).to_a.select(&:buyable?)
      return if offers.empty?

      scores = score_offers(offers)
      ordered = offers.sort_by { |offer| [-scores.fetch(offer.id).total, offer.id] }
      Result.new(winner: ordered.first, offers: ordered, scores: scores)
    end

    def self.eligible_offers(listing)
      Marketplace::Listing.where(
        city_id: listing.city_id,
        category_id: listing.category_id,
        kind: "goods",
        buy_box_key: listing.buy_box_key,
        status: "active"
      ).where.not(store_id: nil)
       .where("expires_at IS NULL OR expires_at > ?", Time.current)
       .joins(:store)
       .merge(Marketplace::Store.active)
       .includes(:store, :user)
    end

    def self.score_offers(offers)
      min_price, max_price = offers.map { |offer| offer.price_cents.to_i }.minmax
      min_delivery, max_delivery = offers.map { |offer| offer.delivery_promise.to_i }.minmax

      offers.to_h do |offer|
        price = max_price == min_price ? 1.0 :
          (max_price - offer.price_cents.to_i).to_f / (max_price - min_price)
        delivery = max_delivery == min_delivery ? 1.0 :
          (max_delivery - offer.delivery_promise.to_i).to_f / (max_delivery - min_delivery)
        performance = offer.seller_score.to_f.clamp(0.0, 1.0)
        stock = [offer.available_quantity.to_i, 10].min / 10.0
        fulfilment = FULFILMENT_SCORES.fetch(offer.fulfilment_method.to_i, 0.25)
        values = { price:, delivery:, performance:, stock:, fulfilment: }
        total = values.sum { |factor, value| WEIGHTS.fetch(factor) * value }
        [offer.id, Score.new(total:, **values)]
      end
    end

    private_class_method :score_offers
    private_class_method :eligible_offers
  end
end
