# frozen_string_literal: true

class Marketplace::CheckoutsController < Marketplace::BaseController
  before_action :require_user_session

  # POST /checkout  provider=stripe|vipps  order_id? (default: all payable cart lines, first)
  def create
    provider = params[:provider].to_s
    order = find_payable_order
    unless order
      redirect_to cart_path, alert: t("flash.marketplace.cart_not_payable")
      return
    end

    url =
      case provider
      when "stripe"
        Marketplace::Payments::StripeCheckout.start!(
          order: order,
          success_url: checkout_url(provider: "stripe", order_id: order.id),
          cancel_url: cart_url
        )
      when "vipps"
        Marketplace::Payments::VippsCheckout.start!(
          order: order,
          return_url: checkout_url(provider: "vipps", order_id: order.id)
        )
      else
        redirect_to cart_path, alert: t("flash.marketplace.unknown_provider")
        return
      end
    redirect_to url, allow_other_host: true
  rescue Marketplace::Payments::NotConfigured => e
    redirect_to cart_path, alert: e.message
  rescue StandardError => e
    Ground::Swallow.log(e, context: "Marketplace::CheckoutsController#create") if defined?(Ground::Swallow)
    redirect_to cart_path, alert: t("flash.marketplace.checkout_failed", message: e.message)
  end

  # GET return from PSP (success path; webhooks remain source of truth when configured)
  def show
    order = Current.user.marketplace_orders.find_by(id: params[:order_id])
    if order&.payment_status == "pending" && params[:provider].present?
      # Without webhook yet, operator can mark paid in admin; here we only show status honestly.
      redirect_to order_path(order), notice: t("flash.marketplace.payment_recorded", status: t("flash.marketplace.payment_statuses.#{order.payment_status}"), provider: order.payment_provider || params[:provider])
    else
      redirect_to cart_path
    end
  end

  private

  def find_payable_order
    scope = Current.user.marketplace_orders.includes(:listing).order(created_at: :desc)
    if params[:order_id].present?
      scope.find_by(id: params[:order_id])
    else
      scope.detect(&:payable?)
    end
  end
end
