# frozen_string_literal: true

# AuthTier — gates all non-public paths behind a token match.
# Visitor requests get 401 Unauthorized; authenticated requests pass through
# with env["master.tier"] = "authenticated". Token lives in .master/config.yml.
class AuthTier
  PUBLIC_PATHS  = %w[/up /health /manifest.json /icon.png /icon.svg /sw.js].freeze
  PUBLIC_PREFIX = %w[/assets/].freeze

  def initialize(app, config_path:)
    @app = app
    @config_path = config_path
  end

  def call(env)
    path = env["PATH_INFO"].to_s
    return @app.call(env) if public?(path)

    if authenticated?(env)
      env["master.tier"] = "authenticated"
      @app.call(env)
    else
      [401, { "content-type" => "text/plain; charset=utf-8" }, ["Unauthorized\n"]]
    end
  end

  private

  def public?(path)
    PUBLIC_PATHS.include?(path) || PUBLIC_PREFIX.any? { |p| path.start_with?(p) }
  end

  def authenticated?(env)
    request = Rack::Request.new(env)
    tok = web_token
    request.params["token"] == tok || env["HTTP_X_TOKEN"] == tok
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
