# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  VISITOR_ALLOWED_TOOLS = %w[AskLlm WebSearch].freeze
  CHAT_RATE_LIMIT = 30  # requests per 60s per IP
  CHAT_WINDOW_S   = 60

  before_action :enforce_chat_rate_limit, only: [:message]

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
    ip  = request.remote_ip.to_s
    key = "master:rl:#{ip}"
    cache = Rails.cache
    count = cache.read(key).to_i
    if count >= CHAT_RATE_LIMIT
      render json: { error: "rate limit exceeded — retry after #{CHAT_WINDOW_S}s" }, status: :too_many_requests
    else
      cache.write(key, count + 1, expires_in: CHAT_WINDOW_S)
    end
  end

  def container
    Rails.application.config.x.master_container
  end

  def start_ms
    Rails.application.config.x.master_start_ms
  end
end
