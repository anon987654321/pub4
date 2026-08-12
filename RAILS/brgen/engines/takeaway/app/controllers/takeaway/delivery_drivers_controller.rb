# frozen_string_literal: true

module Takeaway
  class DeliveryDriversController < ApplicationController
    before_action :set_driver, only: %i[show update]
    before_action :require_real_user, only: :update
    before_action :authorize_owner!, only: :update

    def index
      @delivery_drivers = Takeaway::DeliveryDriver.available.limit(100)
    end

    def show
    end

    def update
      if @delivery_driver.update(driver_params)
        redirect_to delivery_driver_path(@delivery_driver), notice: t("takeaway.driver_updated", default: "Driver updated")
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_driver
      @delivery_driver = Takeaway::DeliveryDriver.find(params[:id])
    end

    def authorize_owner!
      # user_id, not user — @delivery_driver is found by id with nothing
      # preloaded and strict_loading_by_default raises on the association read.
      return if Current.user && Current.user.id == @delivery_driver.user_id

      redirect_to(delivery_driver_path(@delivery_driver), alert: t("shared.flash.not_authorized"))
    end

    def driver_params
      params.require(:delivery_driver).permit(:vehicle_type, :license_number, :available, :current_lat, :current_lng)
    end
  end
end
