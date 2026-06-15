# frozen_string_literal: true

class FoodRequestsController < ApplicationController
  def create
    listing  = FoodListing.find(params[:food_listing_id])
    @request = listing.food_requests.build(request_params.merge(user: Current.user, status: "pending"))
    @request.save ? redirect_to(listing, notice: "Request sent") : render(:new, status: :unprocessable_entity)
  end

  def update
    @request = FoodRequest.find(params[:id])
    authorize_owner!
    @request.update!(status: params[:status]) if params[:status].in?(%w[approved declined])
    redirect_to @request.food_listing
  end

  private

  def authorize_owner! = redirect_to(root_path, alert: "Unauthorized") unless @request.food_listing.user == Current.user
  def request_params   = params.expect(:food_request => [:message, :pickup_time])
end
