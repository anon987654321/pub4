# frozen_string_literal: true

class DealsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @deals = pagy(deals_scope, page: page, request:)
    super
  end

  private

  def page_html
    @deals.map { |deal| render(partial: "marketplace/deals/card", locals: { deal: }) }.join
  end

  def deals_scope
    scope = Marketplace::Deal.active.includes(:listing)
    return scope unless element.dataset["q"].present?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.joins(:listing).where(
      "marketplace_deals.headline LIKE :q OR marketplace_deals.badge LIKE :q OR marketplace_listings.title LIKE :q",
      q: like
    )
  end
end