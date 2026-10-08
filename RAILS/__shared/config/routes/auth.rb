# frozen_string_literal: true

# Shared auth routes — instance_eval from each app's config/routes.rb

resource :account, only: %i[show destroy], controller: "account_settings" do
  post :cancel_deletion, on: :member
  get :export, on: :member
end

resource :two_factor_setup, only: %i[show create update], controller: "two_factor_setups"
post "two_factor/verify" => "two_factor_setups#verify", as: :two_factor_verify

# Every controller named here ships in the engine, as FingerprintsController does — but
# its route lives with the two apps that mount browser-fingerprint and read the cookie.
get "/auth/:provider/callback" => "omniauth_callbacks#create"
post "/auth/:provider" => "omniauth_callbacks#passthru"
