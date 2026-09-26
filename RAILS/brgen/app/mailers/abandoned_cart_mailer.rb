# frozen_string_literal: true

class AbandonedCartMailer < ApplicationMailer
  default from: "Brgen <letters@brgen.no>"

  def reminder(checkout)
    @user = checkout.user
    @checkout = checkout
    @orders = Marketplace::Order.strict_loading(false)
                           .where(marketplace_checkout_id: checkout.id)
                           .includes(:listing, :variant)
    @cart_url = cart_url(host: mail_host, protocol: "https")
    mail to: @user.email_address,
         subject: I18n.t("mailer.abandoned_cart_subject", count: @orders.size)
  end

  private

  def mail_host
    ENV.fetch("APP_HOST", "brgen.no")
  end
end
