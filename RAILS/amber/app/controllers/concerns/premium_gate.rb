# frozen_string_literal: true

# Amber Premium (__shared/config/plans.yml, amber_premium): the AI styling,
# declutter guide and packing lists. The wardrobe, outfits and the declutter
# queue stay free.
#
# The gate shuts only once a Premium plan can be bought. Until the operator
# sets STRIPE_SECRET_KEY and a price id, these features stay free, rather than
# locking readers out of something they have no way to pay for.
module PremiumGate
  extend ActiveSupport::Concern

  class_methods do
    def premium_only(*actions) = before_action(:require_premium, only: actions)
  end

  private

  def require_premium
    return if Current.user&.entitled?(:amber_premium)
    return unless Shared::BillingPlan.for_app("amber").any?(&:available?)

    redirect_to billing_path, notice: t("billing.premium_required")
  end
end
