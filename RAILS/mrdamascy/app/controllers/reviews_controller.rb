# frozen_string_literal: true

class ReviewsController < ApplicationController
  # Posted from the public tracking page after delivery (APP_SPEC §6).
  # Reviews belong to a user, so anonymous trackers are asked to sign in.
  def create
    order = Order.find(params[:id])
    return redirect_to(track_path(order.tracking_token), alert: t("auth.sign_in_first")) unless current_user
    return redirect_to(track_path(order.tracking_token), notice: t("orders.thanks")) if order.review

    # Accepts both the form_with model shape (params[:review][…]) and plain
    # field names, mirroring CheckoutController#checkout_params.
    attrs = params[:review].is_a?(ActionController::Parameters) ? params.require(:review) : params
    order.create_review!(
      user: current_user,
      rating: attrs[:rating].to_i.clamp(1, 5),
      body: attrs[:body].to_s.presence&.truncate(2000)
    )

    redirect_to track_path(order.tracking_token), notice: t("orders.thanks")
  end
end
