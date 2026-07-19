# frozen_string_literal: true

require "json"

# HTTP adapter for OpenClaw (or any channel gateway) → MASTER TurnRouter.
# Auth: Authorization: Bearer <MASTER_BRIDGE_TOKEN>
class BridgeController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :turn
  skip_before_action :require_container!, only: :health
  before_action :require_bridge_token!, except: :health
  before_action :enforce_bridge_rate_limit, only: :turn

  BRIDGE_RATE_LIMIT = 60
  BRIDGE_WINDOW_S = 60

  def health
    c = container
    render json: {
      ok: true,
      service: "master-bridge",
      ready: !c.nil?,
      version: "1",
    }
  end

  def turn
    body = parse_turn_body
    message = body[:message].to_s.strip
    return render(json: { error: "empty message" }, status: :bad_request) if message.empty?

    metadata = Master::Io::OpenclawBridge.gateway_metadata(body)
    elevated = Master::Io::OpenclawBridge.elevated?(body)

    result = Master::Io::IngressRunner.run_turn(
      container: container,
      message: message,
      metadata: metadata,
      elevated: elevated
    )
    render json: bridge_response(result, metadata)
  rescue StandardError => e
    render json: { error: e.message, ok: false }, status: :internal_server_error
  end

  private

  def parse_turn_body
    raw = request.request_parameters.presence
    if raw.nil? || raw.empty?
      raw = JSON.parse(request.body.read) if request.content_type.to_s.include?("json")
    end
    Master::Io::OpenclawBridge.parse_body(raw || {})
  rescue JSON::ParserError
    {}
  end

  def bridge_response(result, metadata)
    agent = container[:agent]
    value = result.ok? ? result.value! : nil
    output = if value.is_a?(Hash)
               value[:rendered] || value[:output] || value.to_s
             else
               value || result.message
             end
    client_actions = value.is_a?(Hash) ? Array(value[:client_actions]) : []
    {
      ok: result.ok?,
      output: output.to_s,
      client_actions: client_actions,
      model: agent&.model.to_s,
      session_key: metadata[:openclaw_session],
      channel: metadata[:openclaw_channel],
      constitutional: true,
    }
  end

  def require_bridge_token!
    header = request.headers["Authorization"].to_s
    token = header.sub(/\ABearer\s+/i, "").strip
    return if MasterBridgeToken.valid?(token)

    render json: { error: "bridge auth required" }, status: :unauthorized
  end

  def enforce_bridge_rate_limit
    enforce_rate_limit!("master:rl:bridge:#{request.remote_ip}", limit: BRIDGE_RATE_LIMIT, window: BRIDGE_WINDOW_S)
  end
end
