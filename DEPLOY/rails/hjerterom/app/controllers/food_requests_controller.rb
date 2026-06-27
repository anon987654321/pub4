# frozen_string_literal: true

class FoodRequestsController < ApplicationController
  def create
    @listing = FoodListing.find(params[:food_listing_id])
    @request = @listing.food_requests.build(request_params.merge(user: Current.user, status: "pending"))
    if @request.save
      @request.record_activity!("FoodRequestCreated", source_vertical: "hjerterom")
      respond_to do |format|
        format.html { redirect_to(@listing, notice: "Request sent") }
        format.turbo_stream
      end
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def update
    @request = FoodRequest.find(params[:id])
    authorize_owner!
    @request.update!(status: params[:status]) if params[:status].in?(%w[accepted declined])
    @request.record_activity!("FoodRequestUpdated", source_vertical: "hjerterom")
    respond_to do |format|
      format.html { redirect_to @request.food_listing }
      format.turbo_stream
    end
  end

  private

  def authorize_owner!
    redirect_to(root_path, alert: "Unauthorized") unless @request.food_listing.user == Current.user
  end

  def request_params = params.require(:food_request).permit(:message, :pickup_time)
end