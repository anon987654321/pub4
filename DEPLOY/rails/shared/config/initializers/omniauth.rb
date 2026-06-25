# frozen_string_literal: true

# AN204: OAuth via OmniAuth (google + github + vipps)

require Shared::Engine.root.join("lib/omniauth/strategies/vipps").to_s

Rails.application.config.middleware.use OmniAuth::Builder do
  if ENV["VIPPS_CLIENT_ID"].present? && ENV["VIPPS_CLIENT_SECRET"].present?
    provider :vipps,
             ENV["VIPPS_CLIENT_ID"],
             ENV["VIPPS_CLIENT_SECRET"]
  end
  if ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
    provider :google_oauth2,
             ENV["GOOGLE_CLIENT_ID"],
             ENV["GOOGLE_CLIENT_SECRET"],
             scope: "email,profile",
             prompt: "select_account"
  end

  if ENV["GITHUB_CLIENT_ID"].present? && ENV["GITHUB_CLIENT_SECRET"].present?
    provider :github,
             ENV["GITHUB_CLIENT_ID"],
             ENV["GITHUB_CLIENT_SECRET"],
             scope: "user:email"
  end
end

OmniAuth.config.allowed_request_methods = %i[post get]
OmniAuth.config.silence_get_warning = true
