# frozen_string_literal: true

require "openssl"

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  VISITOR_ALLOWED_TOOLS = Master::Ground::ToolProfile.public_names.freeze
  AUTHENTICATED_ACTIONS = %i[dmesg history live metrics metrics_prometheus].freeze
  TTS_SYNTH_ACTIONS = %i[show].freeze
  TTS_POLL_ACTIONS = %i[status stream].freeze
  CHAT_RATE_LIMIT = 30  # requests per 60s per IP
  CHAT_WINDOW_S   = 60
  TTS_RATE_LIMIT  = 30
  TTS_WINDOW_S    = 60
  # status/stream are cheap, read-only progress polls — pollTTSJob calls status
  # every 250ms-1.5s per in-flight job, so a couple of concurrent utterances
  # legitimately produce dozens of polls per minute. They used to share
  # TTS_RATE_LIMIT with `show` (the actual synthesis request); polling for an
  # existing job isn't synthesis abuse, and a 429 here made the client's
  # pollTTSJob throw and silently fall back to the browser's native voice —
  # same failure mode as the enqueue race, different trigger. Give polling its
  # own, much larger budget.
  TTS_POLL_RATE_LIMIT = 300
  TTS_POLL_WINDOW_S   = 60
  WEB_READ_RATE_LIMIT  = 120
  WEB_READ_WINDOW_S    = 60
  WEB_WRITE_RATE_LIMIT = 60
  WEB_WRITE_WINDOW_S   = 60

  before_action :set_html_no_store, if: -> { request.format.html? }
  after_action :set_html_no_store, if: -> { request.format.html? }
  before_action :require_container!
  before_action :require_authenticated!, if: -> { action_in?(AUTHENTICATED_ACTIONS) }
  before_action :enforce_chat_rate_limit, if: -> { action_in?(:message) }
  before_action :enforce_tts_rate_limit, if: -> { controller_name == "tts" && action_in?(TTS_SYNTH_ACTIONS) }
  before_action :enforce_tts_poll_rate_limit, if: -> { controller_name == "tts" && action_in?(TTS_POLL_ACTIONS) }
  before_action :enforce_web_read_rate_limit, if: -> { action_in?(%i[dmesg history live metrics]) }
  before_action :enforce_web_write_rate_limit, if: -> { action_in?(%i[command enhance photo post_event state]) }

  private

  def set_html_no_store
    response.headers.delete("ETag")
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0, private"
    response.headers["Pragma"] = "no-cache"
  end

  def action_in?(actions)
    Array(actions).include?(action_name.to_sym)
  end

  def master_tier
    request.env["master.tier"].to_s
  end

  def visitor?
    master_tier != "authenticated"
  end
  helper_method :visitor? if respond_to?(:helper_method)

  def authenticated?
    master_tier == "authenticated"
  end

  def unlocked?
    expected = unlock_cookie_value
    given = cookies[:master_unlocked].to_s
    return false if expected.empty? || given.bytesize != expected.bytesize

    Rack::Utils.secure_compare(given, expected)
  end

  def set_unlock_cookie
    cookies[:master_unlocked] = {
      value: unlock_cookie_value, expires: 1.year.from_now,
      secure: request.ssl?, httponly: true, same_site: :strict,
    }
  end

  def unlock_cookie_value
    secret = MasterWebToken.read.to_s
    return "" if secret.empty?

    OpenSSL::HMAC.hexdigest("SHA256", secret, "master_unlocked")
  end

  def visitor_tool_permitted?(tool_name)
    VISITOR_ALLOWED_TOOLS.include?(tool_name.to_s)
  end

  def require_authenticated!
    return if authenticated?

    respond_to do |fmt|
      fmt.json { render json: { error: "authentication required" }, status: :unauthorized }
      fmt.html { head :unauthorized }
      fmt.any  { head :unauthorized }
    end
  end

  def enforce_visitor_tool!(tool_name)
    return unless visitor?
    return if visitor_tool_permitted?(tool_name)

    head :forbidden
  end

  def pairing_active?
    Master::Ground::Pairing.valid_token?(cookies[:master_paired].to_s)
  end
  helper_method :pairing_active? if respond_to?(:helper_method)

  def face_profile
    Master::Ground::Pairing.face_profile(visitor: visitor?, paired: pairing_active?)
  end
  helper_method :face_profile if respond_to?(:helper_method)

  def pair_redeem_limited?
    count = increment_rate_limit!(
      "master:rl:pair:#{request.remote_ip}",
      window: Master::Ground::Pairing.redeem_window_seconds,
    )
    count > Master::Ground::Pairing.redeem_per_minute
  end

  def enforce_pair_redeem_rate_limit
    return unless pair_redeem_limited?

    response.headers["Retry-After"] = Master::Ground::Pairing.redeem_window_seconds.to_s
    render json: { error: "too many pair attempts — wait a minute" }, status: :too_many_requests
  end

  def set_pair_cookie(token)
    cookies[:master_paired] = {
      value: token, expires: 1.year.from_now,
      secure: request.ssl?, httponly: true, same_site: :strict,
    }
  end

  # Which conversation this browser is having.
  #
  # The container is a process singleton, so Trace::Session held one transcript
  # for every visitor at once and Agent#conversation_context fed the model
  # `messages.last(17)` regardless of who wrote them. /chat/history is auth-
  # gated so the endpoint never leaked; the model did, by answering one person
  # with what another had just said.
  #
  # master_session cannot key this — it is the shared auth token, identical for
  # every authenticated client and absent for visitors, so it names nobody. This
  # is its own opaque id, minted on first use and meaning nothing beyond "same
  # browser". Same attributes as the pair cookie: HttpOnly and SameSite=Strict,
  # so it is not readable from script and does not ride cross-site requests.
  def conversation_id
    existing = cookies[:master_conversation].to_s
    return existing if existing.match?(/\A[0-9a-f]{32}\z/)

    minted = SecureRandom.hex(16)
    cookies[:master_conversation] = {
      value: minted, expires: 1.year.from_now,
      secure: request.ssl?, httponly: true, same_site: :strict,
    }
    minted
  end

  def with_master_fiber(unlocked: false)
    Fiber[:master_visitor] = visitor?
    Fiber[:master_elevated] = unlocked
    Fiber[:master_conversation] = conversation_id
    Master::Ground::Pairing.apply_token!(cookies[:master_paired].to_s)
    yield
  ensure
    Fiber[:master_visitor] = nil
    Fiber[:master_elevated] = nil
    Fiber[:master_paired] = nil
    Fiber[:master_pair_subject] = nil
    # Cleared with the rest: a fiber that keeps this set would serve the next
    # request on this thread someone else's transcript, which is the bug.
    Fiber[:master_conversation] = nil
  end

  def enforce_chat_rate_limit
    enforce_rate_limit!("master:rl:chat:#{request.remote_ip}", limit: CHAT_RATE_LIMIT, window: CHAT_WINDOW_S)
  end

  def enforce_tts_rate_limit
    enforce_rate_limit!("master:rl:tts:#{request.remote_ip}", limit: TTS_RATE_LIMIT, window: TTS_WINDOW_S)
  end

  def enforce_tts_poll_rate_limit
    enforce_rate_limit!("master:rl:tts:poll:#{request.remote_ip}", limit: TTS_POLL_RATE_LIMIT, window: TTS_POLL_WINDOW_S)
  end

  def enforce_web_read_rate_limit
    enforce_rate_limit!("master:rl:web:read:#{request.remote_ip}", limit: WEB_READ_RATE_LIMIT, window: WEB_READ_WINDOW_S)
  end

  def enforce_web_write_rate_limit
    enforce_rate_limit!("master:rl:web:write:#{request.remote_ip}", limit: WEB_WRITE_RATE_LIMIT, window: WEB_WRITE_WINDOW_S)
  end

  def enforce_rate_limit!(key, limit:, window:)
    count = increment_rate_limit!(key, window:)
    return if count <= limit

    response.headers["Retry-After"] = window.to_s
    render json: { error: "rate limit exceeded - wait #{window}s" }, status: :too_many_requests
  end

  def increment_rate_limit!(key, window:)
    cache = Rails.cache
    count = cache.increment(key, 1, expires_in: window)
    return count if count.is_a?(Integer)

    next_count = cache.fetch(key, expires_in: window) { 0 }.to_i + 1
    cache.write(key, next_count, expires_in: window)
    next_count
  end

  def container
    Rails.application.config.x.master_container
  end

  def require_container!
    return if container
    return if warming_exempt_path?

    start_container_bootstrap!

    return if container

    return render_sse_warming! if sse_warming_path?

    respond_to do |fmt|
      fmt.html { render inline: WARMING_HTML, layout: false, status: :ok }
      fmt.json { render json: { error: "warming up" }, status: :service_unavailable }
      fmt.any  { head :service_unavailable }
    end
  end

  def sse_warming_path?
    path = request.path
    path == "/chat/message" || path == "/events/stream"
  end

  def render_sse_warming!
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    body = ": warming\n\ndata: booting — retry in 30s\n\n"
    body += "data: [DONE]\n\n" unless request.path == "/events/stream"
    render plain: body, status: :ok
  end

  def start_container_bootstrap!
    # Bootstrap thread is owned by config/initializers/master_container.rb.
    nil
  end

  def warming_exempt_path?
    path = request.path
    return true if path == "/up" || path == "/health" || path == "/ingress/health"
    return true if path == "/pair" || path.start_with?("/pair/")
    return true if smoke_chat_probe?
    return true if path.start_with?("/assets/", "/runtime/")
    return true if path.match?(%r{\A/(?:face\.|three\.module|chat-|particle_|cognition_|visual_|face3d_|face_|face_vision|face_deferred|topology_|cluster_|domain_cluster|mask|sw\.js|manifest\.json|icon\.|offline\.html)})

    false
  end

  SMOKE_CHAT_MESSAGES = %w[ping pong health up].freeze

  def smoke_chat_probe?
    request.path == "/chat/message" &&
      SMOKE_CHAT_MESSAGES.include?(params[:message].to_s.strip.downcase)
  end

  WARMING_HTML = <<~HTML.freeze
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <title>Starting up…</title>
    <meta http-equiv="refresh" content="5">
    <style>body{background:#000;color:#fff;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
    p{opacity:.6}</style></head>
    <body><p>Starting up, please wait…</p></body></html>
  HTML

  def start_ms
    Rails.application.config.x.master_start_ms
  end
end
