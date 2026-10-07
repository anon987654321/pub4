# frozen_string_literal: true

module Takeaway
  class DeliveryDriversController < ApplicationController
    before_action :set_public_driver, only: :show
    before_action :set_driver, only: :update
    before_action :require_real_user, only: :update
    before_action :authorize_owner!, only: :update

    def index
      @delivery_drivers = Takeaway::DeliveryDriver.publicly_available.includes(:user).limit(100)
    end

    def show
    end

    def update
      return render :show, status: :unprocessable_entity unless @delivery_driver.update(driver_params)

      redirect_to delivery_driver_path(@delivery_driver), notice: t("takeaway.driver_updated")
    end

    private

    def set_public_driver
      @delivery_driver = Takeaway::DeliveryDriver.publicly_visible.includes(:user).find(params[:id])
    end

    def set_driver
      @delivery_driver = Takeaway::DeliveryDriver.includes(:user).find(params[:id])
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
