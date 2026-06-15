# frozen_string_literal: true

module Takeaway
  class DeliveryDriversController < ApplicationController
    before_action :set_driver, only: %i[show update]

    def index
      @delivery_drivers = Takeaway::DeliveryDriver.available.limit(100)
    end

    def show
    end

    def update
      if @delivery_driver.update(driver_params)
        redirect_to takeaway_delivery_driver_path(@delivery_driver), notice: t("takeaway.driver_updated", default: "Driver updated")
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_driver
      @delivery_driver = Takeaway::DeliveryDriver.find(params[:id])
    end

    def driver_params
      params.require(:delivery_driver).permit(:vehicle_type, :license_number, :available, :current_lat, :current_lng)
    end
  end
end
