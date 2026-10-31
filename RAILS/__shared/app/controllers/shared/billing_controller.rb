# frozen_string_literal: true

module Shared
  # /billing: the app's plans from config/plans.yml, the reader's subscription,
  # a checkout to start one and Stripe's portal to change or cancel it. Each app
  # mounts it as BillingController < Shared::BillingController and names itself
  # with billing_app.
  class BillingController < ApplicationController
    before_action :require_authentication

    def show
      @plans = Shared::BillingPlan.for_app(billing_app)
      @subscriptions = Current.user.billing_subscriptions.order(created_at: :desc)
    end

    def create
      plan = selected_plan
      return redirect_to(main_app.billing_path, alert: t("billing.unavailable")) unless plan&.available?

      redirect_to checkout_url_for(plan), allow_other_host: true
    rescue Shared::StripeBilling::Error => e
      Rails.logger.warn("[billing] checkout: #{e.message}")
      redirect_to main_app.billing_path, alert: t("billing.unavailable")
    end

    def portal
      redirect_to Shared::StripeBilling.portal_url(user: Current.user, return_url: main_app.billing_url),
                  allow_other_host: true
    rescue Shared::StripeBilling::Error => e
      Rails.logger.warn("[billing] portal: #{e.message}")
      redirect_to main_app.billing_path, alert: t("billing.unavailable")
    end

    private

    def selected_plan
      plans = Shared::BillingPlan.for_app(billing_app)
      plans.find { |candidate| candidate.key == params[:plan].to_s }
    end

    def checkout_url_for(plan)
      Shared::StripeBilling.checkout_url(user: Current.user, plan:, success_url: main_app.billing_url(started: 1),
                                         cancel_url: main_app.billing_url)
    end

    def billing_app = raise(NotImplementedError, "#{self.class} must define billing_app")
  end
end
