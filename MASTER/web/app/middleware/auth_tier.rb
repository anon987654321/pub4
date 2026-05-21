# frozen_string_literal: true

require "rack/utils"

# AuthTier — sets master.tier for every request and runs the cookie handshake.
# Tiers:
#   "authenticated" — bearer, X-Token header, master_session cookie, or first-hit ?token=
#   "visitor"       — no token; LLM + WebSearch only (tool guard in pipeline)
# Public paths bypass tier logic entirely (health, assets, PWA manifest).
#
# Handshake: a request with a matching ?token= is upgraded — server sets an
# HttpOnly cookie and 302s to the same path with the token stripped. Subsequent
# requests carry the cookie automatically, including EventSource, so the token
# leaves the URL after one hop. Query strings live in proxy logs, browser
# history, and Referer headers; cookies do not.
class AuthTier
  PUBLIC_PATHS   = %w[/up /health /manifest.json /icon.png /icon.svg /sw.js /face.css /face.js].freeze
  PUBLIC_PREFIX  = %w[/assets/].freeze
  TOKEN_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".chars.freeze
  TOKEN_LENGTH   = 16
  COOKIE_NAME    = "master_session"
  COOKIE_MAX_AGE = 60 * 60 * 24 * 30

  def initialize(app, config_path:)
    @app = app
    @config_path = config_path
    @token_mutex = Mutex.new
    @cached_token = nil
    @config_mtime = nil
  end

  def call(env)
    path = env["PATH_INFO"].to_s
    return @app.call(env) if public?(path)

    tok = web_token
    candidate, source = extract_candidate(env)
    authed = !tok.to_s.empty? && !candidate.empty? &&
             Rack::Utils.secure_compare(candidate, tok)
    env["master.tier"] = authed ? "authenticated" : "visitor"

    return handshake_redirect(env, tok) if authed && source == :url

    status, headers, body = @app.call(env)
    headers = with_cookie(headers, env, tok) if authed && source == :url
    [status, headers, body]
  end

  private

  def public?(path)
    PUBLIC_PATHS.include?(path) || PUBLIC_PREFIX.any? { |p| path.start_with?(p) }
  end

  def extract_candidate(env)
    bearer = env["HTTP_AUTHORIZATION"].to_s.sub(/\ABearer\s+/i, "")
    return [bearer, :bearer] unless bearer.empty?

    xtoken = env["HTTP_X_TOKEN"].to_s
    return [xtoken, :header] unless xtoken.empty?

    cookie_tok = parse_cookie(env)
    return [cookie_tok, :cookie] unless cookie_tok.empty?

    url_tok = Rack::Utils.parse_nested_query(env["QUERY_STRING"].to_s)["token"].to_s
    return [url_tok, :url] unless url_tok.empty?

    ["", nil]
  end

  def parse_cookie(env)
    Rack::Utils.parse_cookies(env)[COOKIE_NAME].to_s
  end

  def handshake_redirect(env, tok)
    [302,
     { "Location"       => clean_url(env),
       "Set-Cookie"     => build_cookie(env, tok),
       "Cache-Control"  => "no-store",
       "Content-Length" => "0" },
     []]
  end

  def with_cookie(headers, env, tok)
    headers = headers.dup
    cookie = build_cookie(env, tok)
    existing = headers["Set-Cookie"] || headers["set-cookie"]
    headers["Set-Cookie"] = existing ? "#{existing}\n#{cookie}" : cookie
    headers
  end

  def build_cookie(env, value)
    parts = ["#{COOKIE_NAME}=#{value}", "HttpOnly", "SameSite=Strict",
             "Path=/", "Max-Age=#{COOKIE_MAX_AGE}"]
    parts << "Secure" if https?(env)
    parts.join("; ")
  end

  def https?(env)
    env["rack.url_scheme"] == "https" ||
      env["HTTP_X_FORWARDED_PROTO"].to_s.downcase == "https"
  end

  def clean_url(env)
    path = env["PATH_INFO"].to_s
    remaining = env["QUERY_STRING"].to_s
                  .split("&")
                  .reject { |p| p.start_with?("token=") || p == "token" }
                  .join("&")
    remaining.empty? ? path : "#{path}?#{remaining}"
  end

  def web_token
    @token_mutex.synchronize do
      mtime = File.mtime(@config_path) rescue nil
      if mtime != @config_mtime
        @config_mtime = mtime
        @cached_token = nil
      end
      @cached_token ||= load_or_seed_token
    end
  end

  def load_or_seed_token
    cfg, readable = read_config
    return cfg["web_token"] if cfg["web_token"].to_s.length.positive?
    return nil unless readable
    seed_token(cfg)
  end

  def read_config
    [YAML.safe_load_file(@config_path, permitted_classes: [Symbol], aliases: true) || {}, true]
  rescue Errno::ENOENT
    [{}, true]
  rescue StandardError => e
    warn "auth_tier: config unreadable (#{e.class}): #{e.message} — declining to seed"
    [{}, false]
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
