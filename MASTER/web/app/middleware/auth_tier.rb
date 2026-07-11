# frozen_string_literal: true

require "fileutils"
require "rack/utils"
require "securerandom"
require "yaml"

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
  PUBLIC_PATHS = %w[/up /health /bridge/health /manifest.json /icon.png /icon.svg /sw.js /face.css /face.js].freeze
  PUBLIC_PREFIX = %w[/assets/].freeze
  TOKEN_BYTES = 48
  MIN_TOKEN_LENGTH = 43 # 32 random bytes encoded as urlsafe base64.
  COOKIE_NAME = "master_session"
  COOKIE_MAX_AGE = 60 * 60 * 24 * 30

  def initialize(app, config_path:)
    @app = app
    @config_path = config_path
    @token_mutex = Mutex.new
    @cached_token = nil
    @cached_config_path = nil
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
    qs = Rack::Utils.parse_nested_query(env["QUERY_STRING"].to_s)
    bearer = env["HTTP_AUTHORIZATION"].to_s.sub(/\ABearer\s+/i, "")
    return [bearer, :bearer] unless bearer.empty?

    xtoken = env["HTTP_X_TOKEN"].to_s
    return [xtoken, :header] unless xtoken.empty?

    cookie_tok = parse_cookie(env)
    return [cookie_tok, :cookie] unless cookie_tok.empty?

    url_tok = qs["token"].to_s
    return [url_tok, :url] unless url_tok.empty?

    ["", nil]
  end

  def parse_cookie(env)
    Rack::Utils.parse_cookies(env)[COOKIE_NAME].to_s
  end

  def handshake_redirect(env, tok)
    cookie = build_cookie(env, tok)
    [302,
     { "Location" => clean_url(env),
       "Set-Cookie" => cookie,
       "Cache-Control" => "no-store",
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
      config_path = resolved_config_path
      mtime = File.mtime(config_path) rescue nil
      if config_path != @cached_config_path || mtime != @config_mtime
        @cached_config_path = config_path
        @config_mtime = mtime
        @cached_token = nil
      end
      @cached_token ||= load_or_seed_token(config_path)
    end
  end

  def resolved_config_path
    @config_path.respond_to?(:call) ? @config_path.call.to_s : @config_path.to_s
  end

  def load_or_seed_token(config_path)
    cfg, readable = read_config(config_path)
    candidate = cfg["web_token"].to_s
    return candidate if candidate.length >= MIN_TOKEN_LENGTH

    warn "auth_tier: rotating weak web_token (#{candidate.length} chars)" if candidate.length.positive?
    return nil unless readable

    seed_token(config_path, cfg)
  end

  def read_config(config_path)
    [YAML.safe_load_file(config_path, permitted_classes: [Symbol], aliases: true) || {}, true]
  rescue Errno::ENOENT => _e
    [{}, true]
  rescue StandardError => e
    warn "auth_tier: config unreadable (#{e.class}): #{e.message} — declining to seed"
    [{}, false]
  end

  def seed_token(config_path, cfg)
    FileUtils.mkdir_p(File.dirname(config_path))
    lock_path = "#{config_path}.lock"
    File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      existing = YAML.safe_load_file(config_path, permitted_classes: [Symbol], aliases: true) rescue nil
      if existing.is_a?(Hash) && existing["web_token"].to_s.length >= MIN_TOKEN_LENGTH
        return existing["web_token"]
      end
      tok = SecureRandom.urlsafe_base64(TOKEN_BYTES)
      cfg["web_token"] = tok
      tmp = "#{config_path}.tmp.#{Process.pid}"
      File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(cfg.to_yaml) }
      File.rename(tmp, config_path)
      tok
    end
  end
end
