# frozen_string_literal: true

class CategoryListingsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "marketplace/listings/card", as: :listing

  private

  def scope
    category = Marketplace::Category.find(element.dataset["categoryId"])
    category.listings.active.recent.includes(:user, :category)
  end
end
