# frozen_string_literal: true

class Marketplace::ReviewsController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_listing

  def create
    review = @listing.reviews.build(review_params.merge(user: Current.user))
    if Current.user.latitude.present?
      review.reviewer_lat = Current.user.latitude
      review.reviewer_lng = Current.user.longitude
    end

    if review.save
      redirect_to listing_path(@listing), notice: t("flash.marketplace.review_saved")
    else
      redirect_to listing_path(@listing), alert: review.errors.full_messages.to_sentence
    end
  end

  private

  def set_listing
    @listing = find_by_slug_or_id(Marketplace::Listing, params[:listing_id])
  end

  def review_params
    params.require(:review).permit(:rating, :body)
  end
end
