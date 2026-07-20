# frozen_string_literal: true
# Shared auth routes — instance_eval from each app's config/routes.rb

resource :account, only: %i[show destroy], controller: "account_settings" do
  post :cancel_deletion, on: :member
  get :export, on: :member
end

resource :two_factor_setup, only: %i[show create update], controller: "two_factor_setups"
post "two_factor/verify" => "two_factor_setups#verify", as: :two_factor_verify

get "/auth/:provider/callback" => "omniauth_callbacks#create"
post "/auth/:provider" => "omniauth_callbacks#passthru"
post "fingerprint" => "fingerprints#create"
