# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  VISITOR_ALLOWED_TOOLS = %w[AskLlm WebSearch].freeze
  CHAT_RATE_LIMIT = 30  # requests per 60s per IP
  CHAT_WINDOW_S   = 60
  TTS_RATE_LIMIT  = 30
  TTS_WINDOW_S    = 60

  before_action :enforce_chat_rate_limit, only: [:message]
  before_action :enforce_tts_rate_limit, only: [:tts]

  private

  def visitor?
    request.env["master.tier"] != "authenticated"
  end
  helper_method :visitor? if respond_to?(:helper_method)

  def visitor_tool_permitted?(tool_name)
    VISITOR_ALLOWED_TOOLS.include?(tool_name.to_s)
  end

  def enforce_visitor_tool!(tool_name)
    return unless visitor?
    return if visitor_tool_permitted?(tool_name)
    render json: { error: "tool not permitted for visitors: #{tool_name}" }, status: :forbidden
  end

  def enforce_chat_rate_limit
    enforce_rate_limit!("master:rl:chat:#{request.remote_ip}", limit: CHAT_RATE_LIMIT, window: CHAT_WINDOW_S)
  end

  def enforce_tts_rate_limit
    enforce_rate_limit!("master:rl:tts:#{request.remote_ip}", limit: TTS_RATE_LIMIT, window: TTS_WINDOW_S)
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
