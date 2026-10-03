# frozen_string_literal: true

class DealsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "marketplace/deals/card", as: :deal, wrap_in: :li

  private

  def scope
    scope = Marketplace::Deal.live.includes(:listing)
    query = element.dataset["q"]
    query.present? ? scope.matching(query) : scope
  end
end
