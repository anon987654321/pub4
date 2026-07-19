# frozen_string_literal: true

class AffiliateLinksController < ApplicationController
  before_action :require_real_user

  def create
    item = Current.user.items.find(params[:item_id])
    link = item.affiliate_links.build(affiliate_params)
    if link.save
      redirect_to item, notice: "Affiliate link saved"
    else
      redirect_to item, alert: link.errors.full_messages.to_sentence
    end
  end

  def destroy
    item = Current.user.items.find(params[:item_id])
    item.affiliate_links.find(params[:id]).destroy
    redirect_to item, notice: "Affiliate link removed"
  end

  private

  def affiliate_params
    params.require(:affiliate_link).permit(:url, :merchant, :commission_rate)
  end
end
