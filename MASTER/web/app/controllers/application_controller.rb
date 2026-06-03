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

  before_action :require_authenticated!, only: AUTHENTICATED_ACTIONS
  before_action :enforce_chat_rate_limit, only: [:message]
  before_action :enforce_tts_rate_limit, only: [:tts]
  before_action :enforce_web_read_rate_limit, only: %i[dmesg history live metrics]
  before_action :enforce_web_write_rate_limit, only: %i[command enhance photo post_event state]

  private

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

  def start_ms
    Rails.application.config.x.master_start_ms
  end
end
