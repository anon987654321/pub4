# frozen_string_literal: true

class EmailSubscriptionsController < ApplicationController
  skip_before_action :require_real_user, raise: false
  # create takes an arbitrary address from a guest and queues
  # EmailSubscriptionConfirmationJob against it. Unlimited, that is not a signup
  # form, it is a way to make brgen.no send mail to anyone at whatever rate the
  # sender likes — and the mail arrives with our SPF and DKIM on it, so the cost
  # of the abuse lands on the domain's reputation rather than on the sender.
  # Five per ten minutes matches EmailVerificationsController, the other endpoint
  # here whose side effect is an outbound message.
  # name: on every rate_limit in a controller that has more than one. Without it
  # the cache key is ["rate-limit", controller_path, nil, by] — the same string
  # for both — so the two limits increment one shared counter and the tighter one
  # answers for both. See RAILS/test/rate_limit_naming_test.rb.
  rate_limit to: 5, within: 10.minutes, only: :create, name: "subscribe",
    with: -> { redirect_back fallback_location: root_path, alert: t("shared.flash.rate_limited") }
  # confirm and destroy look up a row by a bare `token` column. That token is
  # SecureRandom.urlsafe_base64(32), so this is defence in depth and not a live
  # hole — guessing one is not a thing an attacker gets to do. It is here because
  # the property that makes it safe lives in a `before_create` in another file,
  # and "unguessable" is a claim about a token generator that nothing stops
  # someone shortening. A limit costs one line and does not depend on that.
  rate_limit to: 30, within: 1.minute, only: %i[confirm show update destroy one_click], name: "token_lookup",
    with: -> { redirect_to root_path, alert: t("shared.flash.rate_limited") }
  # RFC 8058 one-click: the mail client POSTs from no page and no session, so
  # there is no CSRF token to check. The bearer is the unguessable token in the
  # List-Unsubscribe URL, and all it can do is stop marketing mail.
  skip_forgery_protection only: :one_click

  def create
    unless params.dig(:email_subscription, :agreed_to_marketing) == "1"
      redirect_back fallback_location: root_path, alert: t("newsletter_popup.consent_required")
      return
    end

    sub = EmailSubscription.find_or_initialize_by(email: params.dig(:email_subscription, :email))
    if sub.new_record? || !sub.agreed_to_marketing?
      reconfirm = sub.persisted?
      city = params.dig(:email_subscription, :city).presence
      interests = params.dig(:email_subscription, :interests).presence
      sub.city = city if sub.new_record? || city.present?
      sub.locale = I18n.locale.to_s
      sub.interests = interests if sub.new_record? || interests.present?

      if sub.record_marketing_consent!(source: "signup_form", reconfirm:)
        EmailSubscriptionConfirmationJob.perform_later(sub.id)
        redirect_back fallback_location: root_path, notice: t("flash.confirm_your_inbox")
      else
        redirect_back fallback_location: root_path, alert: sub.errors.full_messages.first
      end
    else
      redirect_back fallback_location: root_path, notice: t("flash.already_subscribed")
    end
  end
  def show
    @subscription = find_subscription
  end

  def update
    subscription = find_subscription
    subscription.update_marketing_preferences!(marketing: params.dig(:email_subscription, :marketing) == "1")
    redirect_to email_subscription_path(token: subscription.token), notice: t("email_preferences.updated")
  end

  def confirm
    sub = EmailSubscription.find_by!(token: params[:token])
    if sub.confirmed?
      redirect_to root_path, notice: t("flash.already_confirmed")
    else
      sub.confirm!
      redirect_to root_path, notice: t("flash.subscribed")
    end
  end

  def destroy
    sub = find_subscription
    sub.destroy!
    redirect_to root_path, notice: t("flash.unsubscribed")
  end

  def one_click
    subscription = EmailSubscription.find_by(token: params[:token])
    return head :not_found unless subscription

    subscription.revoke_marketing_consent!(source: "one_click")
    head :ok
  end

  private

  def find_subscription = EmailSubscription.find_by!(token: params[:token])
end
