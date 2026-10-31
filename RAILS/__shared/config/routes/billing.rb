# frozen_string_literal: true

# Paid plans (Shared::BillingController, plans in __shared/config/plans.yml).
# instance_eval from each app's config/routes.rb that sells one.
resource :billing, only: %i[show create], controller: "billing" do
  post :portal
end
