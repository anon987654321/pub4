# frozen_string_literal: true

class ReviewsController < ApplicationController
  # Posted from the public tracking page after delivery (APP_SPEC §6).
  # Reviews belong to a user, so anonymous trackers are asked to sign in.
  #
  # The order is looked up among the signed-in customer's own orders. It was
  # Order.find on the sequential id, so anyone could review anyone's order, and
  # every answer redirected to that order's tracking page: walking the ids
  # handed out every customer's private tracking token.
  def create
    return redirect_to(new_session_path, alert: t("auth.sign_in_first")) unless current_user

    order = current_user.orders.find_by(id: params[:id])
    return head(:not_found) unless order
    return redirect_to(track_path(order.tracking_token), notice: t("orders.thanks")) if order.review

    order.create_review!(user: current_user, rating: review_attrs[:rating].to_i.clamp(1, 5),
                         body: review_attrs[:body].to_s.presence&.truncate(2000))
    redirect_to track_path(order.tracking_token), notice: t("orders.thanks")
  end

  private

  # Accepts both the form_with model shape (params[:review][…]) and plain
  # field names, mirroring CheckoutController#checkout_params.
  def review_attrs
    params[:review].is_a?(ActionController::Parameters) ? params.require(:review) : params
  end
end
