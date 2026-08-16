# frozen_string_literal: true

class DealsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "marketplace/deals/card", as: :deal

  private

  def scope
    scope = Marketplace::Deal.live.includes(:listing)
    return scope unless element.dataset["q"].present?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.joins(:listing).where(
      "marketplace_deals.headline LIKE :q OR marketplace_deals.badge LIKE :q OR marketplace_listings.title LIKE :q",
      q: like
    )
  end
end
