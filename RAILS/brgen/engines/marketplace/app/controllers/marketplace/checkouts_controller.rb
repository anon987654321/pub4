# frozen_string_literal: true

class Marketplace::CheckoutsController < Marketplace::BaseController
  before_action :require_user_session

  # POST /checkout  provider=stripe|vipps  order_id? (default: all payable cart lines, first)
  def create
    provider = params[:provider].to_s
    order = find_payable_order
    unless order
      redirect_to cart_path, alert: "Cart has no payable items"
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
        redirect_to cart_path, alert: "Unknown payment provider"
        return
      end
    redirect_to url, allow_other_host: true
  rescue Marketplace::Payments::NotConfigured => e
    redirect_to cart_path, alert: e.message
  rescue StandardError => e
    Ground::Swallow.log(e, context: "Marketplace::CheckoutsController#create") if defined?(Ground::Swallow)
    redirect_to cart_path, alert: "Checkout failed: #{e.message}"
  end

  # GET return from PSP (success path; webhooks remain source of truth when configured)
  def show
    order = Current.user.marketplace_orders.find_by(id: params[:order_id])
    if order&.payment_status == "pending" && params[:provider].present?
      # Without webhook yet, operator can mark paid in admin; here we only show status honestly.
      redirect_to order_path(order), notice: "Payment #{order.payment_status} via #{order.payment_provider || params[:provider]}"
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
