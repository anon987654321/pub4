# frozen_string_literal: true

# /api: what the MASTER law API does, its plans and a checkout; /api/key: the
# page Stripe returns to, which shows a new key once. Plain HTML, no script.
class ApiController < ActionController::Base
  SESSION_ID = /\Acs_[A-Za-z0-9_]{8,200}\z/

  before_action :no_store

  def show
    @plans = Shared::BillingPlan.for_app("master")
  end

  def checkout
    plan = Shared::BillingPlan.for_app("master").find { |candidate| candidate.key == params[:plan].to_s }
    return redirect_to(api_path, alert: t("api.unavailable")) unless plan&.available?

    redirect_to checkout_url_for(plan), allow_other_host: true
  rescue Shared::StripeBilling::Error => e
    Rails.logger.warn("[api] checkout: #{e.message}")
    redirect_to api_path, alert: t("api.unavailable")
  end

  # The key is shown here once. A second visit, or a reload, says it was shown.
  def key
    session_id = params[:session_id].to_s
    return redirect_to(api_path) unless SESSION_ID.match?(session_id)

    @api_key, @token = reveal(Shared::StripeBilling.completed_checkout(session_id))
  rescue Shared::StripeBilling::Error => e
    Rails.logger.warn("[api] key: #{e.message}")
    redirect_to api_path, alert: t("api.not_confirmed")
  end

  private

  # Stripe fills {CHECKOUT_SESSION_ID} itself, so the braces must reach it
  # unescaped; a url helper with a query would encode them.
  def checkout_url_for(plan)
    returns = { success_url: "#{api_key_url}?session_id={CHECKOUT_SESSION_ID}", cancel_url: api_url }
    Shared::StripeBilling.subscription_checkout_url(plan:, returns:)
  end

  def reveal(session)
    api_key = ApiKey.sync!(session.fetch("subscription"), email: session.dig("customer_details", "email"))
    raise Shared::StripeBilling::Error, "checkout #{session["id"]} is not a law API plan" unless api_key

    [api_key, api_key.reveal!]
  end

  def no_store = response.headers["Cache-Control"] = "no-store"
end
