# frozen_string_literal: true

require Shared::Engine.root.join("lib/omniauth/strategies/vipps").to_s if File.exist?(Shared::Engine.root.join("lib/omniauth/strategies/vipps.rb"))
require Shared::Engine.root.join("lib/omniauth/strategies/bankid").to_s if File.exist?(Shared::Engine.root.join("lib/omniauth/strategies/bankid.rb"))

Rails.application.config.x.oauth_provider_slugs = []
# POST only. shared/_oauth_links renders every provider with button_to.
OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.silence_get_warning = true

register_provider = lambda do |builder, name, client_id_env, client_secret_env, options = {}|
  client_id = ENV[client_id_env].presence
  client_secret = ENV[client_secret_env].presence
  return unless client_id && client_secret

  builder.provider name, client_id, client_secret, options
  Rails.application.config.x.oauth_provider_slugs << name.to_s
rescue LoadError, NameError, NoMethodError => error
  Rails.logger.warn("omniauth provider #{name} unavailable: #{error.class}: #{error.message}")
end

Rails.application.config.middleware.use OmniAuth::Builder do
  register_provider.call(self, :google_oauth2, "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET",
    scope: "email,profile", prompt: "select_account")
  register_provider.call(self, :facebook, "FACEBOOK_CLIENT_ID", "FACEBOOK_CLIENT_SECRET",
    scope: "email,public_profile")
  register_provider.call(self, :vipps, "VIPPS_CLIENT_ID", "VIPPS_CLIENT_SECRET",
    scope: "openid email name phoneNumber")

  bankid_environment = ENV.fetch("BANKID_OIDC_ENV", "production").downcase
  if %w[production current].include?(bankid_environment)
    register_provider.call(self, :bankid, "BANKID_CLIENT_ID", "BANKID_CLIENT_SECRET",
      scope: "openid profile", environment: bankid_environment)
  else
    Rails.logger.warn("omniauth provider bankid unavailable: BANKID_OIDC_ENV must be production or current")
  end
end
