# frozen_string_literal: true

# The MASTER law API is sold on the shared billing core: the plans
# (__shared/config/plans.yml), the Stripe client and the webhook signature
# check, and the bets in config/portfolio.yml. This app does not mount the
# shared engine, so it loads those plain Ruby files itself. master runs in
# place in the checkout (apps.yml deploy_root: RAILS/master), so
# RAILS/__shared is always beside it.
shared = File.expand_path("../../../__shared", __dir__)
files = %w[app/services/shared/stripe_signature app/services/shared/stripe_billing app/models/shared/billing_plan
           app/models/shared/portfolio_bet app/services/shared/portfolio_report]
files.each do |file|
  require File.join(shared, file)
end
I18n.load_path += Dir[File.join(shared, "config/locales/billing.*.yml")]
