# frozen_string_literal: true

require Shared::Engine.root.join("lib/omniauth/strategies/vipps").to_s if File.exist?(Shared::Engine.root.join("lib/omniauth/strategies/vipps.rb"))

Rails.application.config.x.oauth_provider_slugs = []
# POST only. shared/_oauth_links renders every provider with button_to, so GET
# is reachable by nobody but a cross-site request; brgen carried a whole second
# copy of this file whose one real difference was tightening this, and the copy
# also lost Google its scope and prompt because app initializers load last.
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
  register_provider.call(self, :github, "GITHUB_CLIENT_ID", "GITHUB_CLIENT_SECRET", scope: "user:email")
  register_provider.call(self, :vipps, "VIPPS_CLIENT_ID", "VIPPS_CLIENT_SECRET",
    scope: "openid email name phoneNumber")
  register_provider.call(self, :snapchat, "SNAPCHAT_CLIENT_ID", "SNAPCHAT_CLIENT_SECRET",
    scope: "https://auth.snapchat.com/oauth2/api/user.display_name")
end
