OmniAuth.config.logger = Rails.logger

# -------------------------------------------------

# Facebook logins

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :facebook, ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_SECRET"], scope: "email,publish_stream"
end

# -------------------------------------------------

# Google logins

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"]
end

# -------------------------------------------------

# Instagram logins

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :instagram, ENV["INSTAGRAM_ID"], ENV["INSTAGRAM_SECRET"]
end

