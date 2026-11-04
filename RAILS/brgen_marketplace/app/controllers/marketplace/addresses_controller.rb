# frozen_string_literal: true

class Marketplace::AddressesController < Marketplace::BaseController
  before_action :require_user_session

  def index
    @addresses = Current.user.marketplace_addresses.default_first
    @address = Marketplace::Address.new(country_code: "NO")
    # A buyer sent here from the cart (its links, or checkout's "address
    # needed" redirect, which keeps the cart as referrer) goes back to it once
    # an address is saved. Only the cart is accepted, never a URL from outside.
    @return_to = cart_path if params[:return_to] == cart_path || referred_by_cart?
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

    unless address.save
      return redirect_back(fallback_location: addresses_path, alert: address.errors.full_messages.to_sentence)
    end

    after_save(t("flash.marketplace.address_saved"))
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

  def after_save(notice)
    return redirect_to(cart_path, notice:) if params[:return_to] == cart_path

    redirect_back fallback_location: addresses_path, notice:
  end

  def referred_by_cart?
    URI.parse(request.referer.to_s).path == cart_path
  rescue URI::InvalidURIError
    false
  end

  # The form is scoped marketplace_address (the model's param key, which
  # form_with uses); requiring :address rejected every save from the page.
  def address_params
    params.require(:marketplace_address).permit(
      :recipient, :line1, :line2, :postcode, :city_name, :country_code, :phone
    )
  end
end
