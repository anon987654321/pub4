# frozen_string_literal: true

require "rack/utils"

# AuthTier — gates all non-public paths behind a token match.
# Visitor requests get 401 Unauthorized; authenticated requests pass through
# with env["master.tier"] = "authenticated". Token lives in .master/config.yml.
class AuthTier
  PUBLIC_PATHS  = %w[/up /health /manifest.json /icon.png /icon.svg /sw.js /face.css /face.js].freeze
  PUBLIC_PREFIX = %w[/assets/].freeze
  # Crockford base32 — no I/L/O/U, easy to read aloud.
  TOKEN_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".chars.freeze
  TOKEN_LENGTH   = 16

  def initialize(app, config_path:)
    @app = app
    @config_path = config_path
    @token_mutex = Mutex.new
    @cached_token = nil
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
    return false if tok.to_s.empty?
    candidate = (request.params["token"] || env["HTTP_X_TOKEN"]).to_s
    Rack::Utils.secure_compare(candidate, tok)
  end

  def web_token
    @token_mutex.synchronize do
      @cached_token ||= load_or_seed_token
    end
  end

  def load_or_seed_token
    cfg, readable = read_config
    return cfg["web_token"] if cfg["web_token"].to_s.length.positive?
    # Refuse to overwrite a config we couldn't read — that would clobber other keys.
    return nil unless readable
    seed_token(cfg)
  end

  def read_config
    return [YAML.safe_load_file(@config_path, permitted_classes: [Symbol], aliases: true) || {}, true]
  rescue Errno::ENOENT => _e
    [{}, true]   # missing file is fine — we can create it
  rescue StandardError => e
    warn "auth_tier: config unreadable (#{e.class}): #{e.message} — declining to seed"
    [{}, false]  # unreadable existing file — never overwrite
  end

  def seed_token(cfg)
    require "securerandom"
    tok = Array.new(TOKEN_LENGTH) { TOKEN_ALPHABET.sample(random: SecureRandom) }.join
    cfg["web_token"] = tok
    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, cfg.to_yaml)
    tok
  end
end
