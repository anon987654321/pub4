# frozen_string_literal: true

# AuthTier — sets request env["master.tier"] to "authenticated" or "visitor"
# based on token match. Public paths bypass entirely. Token comes from
# .master/config.yml; first request seeds it if missing.
class AuthTier
  PUBLIC_PATHS = %w[/up /health].freeze

  def initialize(app, config_path:)
    @app = app
    @config_path = config_path
  end

  def call(env)
    return @app.call(env) if PUBLIC_PATHS.include?(env["PATH_INFO"])
    env["master.tier"] = tier_for(env)
    @app.call(env)
  end

  private

  def tier_for(env)
    request = Rack::Request.new(env)
    token = web_token
    return "authenticated" if request.params["token"] == token
    return "authenticated" if env["HTTP_X_TOKEN"] == token
    "visitor"
  end

  def web_token
    cfg = YAML.safe_load_file(@config_path, permitted_classes: [], aliases: true) rescue {}
    cfg["web_token"].to_s.empty? ? seed_token(cfg) : cfg["web_token"]
  end

  def seed_token(cfg)
    require "securerandom"
    tok = SecureRandom.urlsafe_base64(24)
    cfg["web_token"] = tok
    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, cfg.to_yaml)
    tok
  end
end
