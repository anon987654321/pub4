# frozen_string_literal: true

class Takeaway::ReviewsController < Takeaway::BaseController
  before_action :set_restaurant

  def create
    unless authenticated?
      redirect_to(main_app.new_session_path, alert: t("flash.takeaway.review_requires_sign_in"))
      return
    end

    user = Current.user
    delivered_orders = Takeaway::Order.where(user: user, restaurant: @restaurant, status: "delivered")
    has_delivered = delivered_orders.exists?
    unless has_delivered
      redirect_to(restaurant_path(@restaurant), alert: t("flash.takeaway.review_requires_delivery"))
      return
    end

    # note: unique(order,user) + delivered gate; no mutex needed
    # law_of_demeter: direct model context here is fine for reviews
    review = @restaurant.reviews.build(review_params.merge(user: user, order: delivered_orders.first))
    Shared::ReviewGeoStamp.apply!(review, user)

    if review.save
      @restaurant.update_rating!
      redirect_to(restaurant_path(@restaurant), notice: t("flash.takeaway.review_saved"))
    else
      redirect_to(restaurant_path(@restaurant), alert: review.errors.full_messages.to_sentence)
    end
  end

  private

  def set_restaurant
    @restaurant = find_by_slug_or_id(Takeaway::Restaurant, params[:restaurant_id])
  end

  def review_params
    params.require(:takeaway_review).permit(:rating, :body)
  end
end
