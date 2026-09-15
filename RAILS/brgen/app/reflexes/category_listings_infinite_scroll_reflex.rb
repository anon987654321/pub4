# frozen_string_literal: true

class CategoryListingsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "marketplace/listings/card", as: :listing

  private

  def scope
    category = Marketplace::Category.find(element.dataset["categoryId"])
    # The sort the first page was drawn in, or page two comes back newest first.
    category.listings.live.with_attached_photos.includes(:user, :category).sorted_by(element.dataset["sort"])
  end
end
