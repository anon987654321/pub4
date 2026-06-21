# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  VISITOR_ALLOWED_TOOLS = %w[AskLlm WebSearch].freeze
  AUTHENTICATED_ACTIONS = %i[
    command dmesg enhance history live metrics photo post_event state stream tts
  ].freeze
  CHAT_RATE_LIMIT = 30  # requests per 60s per IP
  CHAT_WINDOW_S   = 60
  TTS_RATE_LIMIT  = 30
  TTS_WINDOW_S    = 60
  WEB_READ_RATE_LIMIT  = 120
  WEB_READ_WINDOW_S    = 60
  WEB_WRITE_RATE_LIMIT = 60
  WEB_WRITE_WINDOW_S   = 60

  before_action :require_container!
  before_action :require_authenticated!, if: -> { action_in?(AUTHENTICATED_ACTIONS) }
  before_action :enforce_chat_rate_limit, if: -> { action_in?(:message) }
  before_action :enforce_tts_rate_limit, if: -> { action_in?(:tts) }
  before_action :enforce_web_read_rate_limit, if: -> { action_in?(%i[dmesg history live metrics]) }
  before_action :enforce_web_write_rate_limit, if: -> { action_in?(%i[command enhance photo post_event state]) }

  private

  def action_in?(actions)
    Array(actions).include?(action_name.to_sym)
  end

  def visitor?
    false
  end
  helper_method :visitor? if respond_to?(:helper_method)

  def visitor_tool_permitted?(_tool_name)
    true
  end

  def require_authenticated!
  end

  def enforce_visitor_tool!(_tool_name)
  end

  def enforce_chat_rate_limit
    enforce_rate_limit!("master:rl:chat:#{request.remote_ip}", limit: CHAT_RATE_LIMIT, window: CHAT_WINDOW_S)
  end

  def enforce_tts_rate_limit
    enforce_rate_limit!("master:rl:tts:#{request.remote_ip}", limit: TTS_RATE_LIMIT, window: TTS_WINDOW_S)
  end

  def enforce_web_read_rate_limit
    enforce_rate_limit!("master:rl:web:read:#{request.remote_ip}", limit: WEB_READ_RATE_LIMIT, window: WEB_READ_WINDOW_S)
  end

  def enforce_web_write_rate_limit
    enforce_rate_limit!("master:rl:web:write:#{request.remote_ip}", limit: WEB_WRITE_RATE_LIMIT, window: WEB_WRITE_WINDOW_S)
  end

  def enforce_rate_limit!(key, limit:, window:)
    cache = Rails.cache
    count = cache.read(key).to_i
    if count >= limit
      response.headers["Retry-After"] = window.to_s
      render json: { error: "rate limit exceeded - retry after #{window}s" }, status: :too_many_requests
    else
      cache.write(key, count + 1, expires_in: window)
    end
  end

  def container
    Rails.application.config.x.master_container
  end

  def require_container!
    return if container
    return if warming_exempt_path?

    MasterContainerLoader.ensure!

    return if container

    respond_to do |fmt|
      fmt.html { render inline: WARMING_HTML, layout: false, status: :service_unavailable }
      fmt.json { render json: { error: "warming up" }, status: :service_unavailable }
      fmt.any  { head :service_unavailable }
    end
  end

  def warming_exempt_path?
    path = request.path
    return true if path == "/up" || path == "/health"
    return true if path.start_with?("/assets/")
    return true if path.match?(%r{\A/(?:face\.|three\.module|chat-|particle_|cognition_|visual_|face3d_|topology_|cluster_|mask|sw\.js|manifest\.json|icon\.|offline\.html)})

    false
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
