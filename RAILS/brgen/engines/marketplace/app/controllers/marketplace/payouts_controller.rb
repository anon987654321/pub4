# frozen_string_literal: true

module Marketplace
  class PayoutsController < Marketplace::BaseController
    before_action :require_real_user
    before_action :set_store
    before_action :authorize_owner

    def create
      payout = @store.payouts.pending.find(params.require(:payout_id))
      payout.release!
      redirect_to shop_path(@store.slug), notice: t("marketplace.payout_sent")
    rescue Marketplace::Payments::NotConfigured
      redirect_to shop_path(@store.slug), alert: t("marketplace.payout_not_configured")
    rescue ArgumentError => error
      redirect_to shop_path(@store.slug), alert: payout_alert(error)
    end

    private

    def set_store
      @store = Marketplace::Store.find_by!(slug: params[:shop_id])
    end

    def authorize_owner
      return if Current.user && @store.owner_id == Current.user.id

      redirect_to shop_path(@store.slug), alert: t("marketplace.store_not_allowed")
    end

    def payout_alert(error)
      return t("marketplace.payout_held") if error.message.include?("held")

      t("marketplace.payout_not_pending")
    end
  end
end
