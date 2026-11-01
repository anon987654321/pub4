# frozen_string_literal: true

# The saved-listings grid. Named for the surface rather than the model,
# because ListingsInfiniteScrollReflex is the public marketplace index and
# this one is scoped to the viewer's own favourites.
#
# Scope copied from Marketplace::FavoritesController#index, including `live`:
# a sold or withdrawn listing leaves the list on its own, and page two must
# agree with page one about that.
class SavedListingsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "marketplace/listings/card", as: :listing, wrap_in: :li

  private

  def scope
    Marketplace::Listing
      .where(id: Marketplace::ListingFavorite.where(user_id: Current.user.id).select(:listing_id))
      .live.with_attached_photos.includes(:user, :category).recent
  end
end
