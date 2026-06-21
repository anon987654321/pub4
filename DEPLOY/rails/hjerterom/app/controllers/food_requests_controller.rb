# frozen_string_literal: true

class FoodRequestsController < ApplicationController
  def create
    listing  = FoodListing.find(params[:food_listing_id])
    @request = listing.food_requests.build(request_params.merge(user: Current.user, status: "pending"))
    if @request.save
      @request.record_activity!("FoodRequestCreated", source_vertical: "hjerterom")
      redirect_to(listing, notice: "Request sent")
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def update
    @request = FoodRequest.find(params[:id])
    authorize_owner!
    @request.update!(status: params[:status]) if params[:status].in?(%w[approved declined])
    @request.record_activity!("FoodRequestUpdated", source_vertical: "hjerterom")
    redirect_to @request.food_listing
  end

  private

  def authorize_owner!
    redirect_to(root_path, alert: "Unauthorized") unless @request.food_listing.user == Current.user
  end
  def request_params   = params.require(:food_request).permit(:message, :pickup_time)
end
