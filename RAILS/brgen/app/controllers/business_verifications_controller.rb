# frozen_string_literal: true

# A business owner asking for the verified badge. The review is
# Admin::BusinessVerificationsController; this side only files the request.
class BusinessVerificationsController < ApplicationController
  # The short names a form or a link carries, mapped to the business types
  # BusinessVerification admits. A class name never travels in a parameter.
  KINDS = { "store" => "Marketplace::Store", "restaurant" => "Takeaway::Restaurant" }.freeze

  before_action :require_user_session
  before_action :set_business

  def new
    @verification = BusinessVerification.new(business: @business)
  end

  def create
    @verification = BusinessVerification.new(
      business: @business,
      requested_by: Current.user,
      **params.require(:business_verification).permit(:legal_name, :organisation_number).to_h.symbolize_keys,
    )
    if @verification.save
      redirect_to business_page, notice: t("flash.business_verifications.sent")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def business_page
    @business.is_a?(Takeaway::Restaurant) ? takeaway.restaurant_path(@business) : marketplace.shop_path(@business.slug)
  end

  # Found under the requesting host's tenant, and refused unless the reader
  # owns it: nobody asks for a badge on somebody else's shop.
  def set_business
    type = KINDS[params[:kind].to_s]
    owner_key = type && BusinessVerification::OWNER_KEYS[type]
    @business = type&.constantize&.find_by(id: params[:business_id])
    @kind = params[:kind].to_s
    return if @business && @business.public_send(owner_key) == Current.user.id

    redirect_to(main_app.root_path, alert: t("shared.flash.not_authorized"))
  end
end
