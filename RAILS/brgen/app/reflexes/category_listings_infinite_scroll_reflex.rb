# frozen_string_literal: true

class CategoryListingsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @listings = pagy(listings_scope, page: page, request:)
    super
  end

  private

  def page_html
    @listings.map { |listing| render(partial: "marketplace/listings/card", locals: { listing: }) }.join
  end

  def listings_scope
    category = Marketplace::Category.find(element.dataset["categoryId"])
    category.listings.active.recent.includes(:user, :category)
  end
end