# frozen_string_literal: true

class Marketplace::AddressesController < Marketplace::BaseController
  before_action :require_user_session

  def index
    @addresses = Current.user.marketplace_addresses.default_first
    @address = Marketplace::Address.new(country_code: "NO")
  end

  def create
    # Asked before building: `marketplace_addresses.new` puts the unsaved
    # record into the association target, so `.none?` afterwards is already
    # false and the first address would never have become the default.
    first_one = !Marketplace::Address.exists?(user_id: Current.user.id)

    address = Current.user.marketplace_addresses.new(address_params)
    # The first address a buyer saves is their default, without asking. Making
    # someone tick a box on a list of one is ceremony.
    address.default_address = true if first_one

    if address.save
      redirect_back fallback_location: addresses_path, notice: t("flash.marketplace.address_saved")
    else
      redirect_back fallback_location: addresses_path, alert: address.errors.full_messages.to_sentence
    end
  end

  def update
    address = Current.user.marketplace_addresses.find(params[:id])
    address.update!(default_address: true)
    redirect_back fallback_location: addresses_path, notice: t("flash.marketplace.address_default")
  end

  def destroy
    Current.user.marketplace_addresses.find(params[:id]).destroy
    redirect_back fallback_location: addresses_path, notice: t("flash.marketplace.address_removed")
  end

  private

  def address_params
    params.require(:address).permit(
      :recipient, :line1, :line2, :postcode, :city_name, :country_code, :phone
    )
  end
end
