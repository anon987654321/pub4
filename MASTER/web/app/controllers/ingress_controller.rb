# frozen_string_literal: true

require "json"

# Webhook + cron ingress (OpenCrabs cron / OpenClaw hooks parity).
# Auth: Authorization: Bearer <MASTER_INGRESS_TOKEN>
class IngressController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_container!, only: :health
  before_action :require_ingress_token!, except: :health
  before_action :enforce_ingress_rate_limit, except: :health

  INGRESS_RATE_LIMIT = 30
  INGRESS_WINDOW_S = 60

  def health
    render json: {
      ok: true,
      service: "master-ingress",
      cron_jobs: Master::Ground::IngressJobs.cron_jobs.map { |j| j["name"] },
      webhooks: Master::Ground::IngressJobs.webhook_jobs.map { |j| j["name"] },
    }
  end

  def cron
    job = Master::Ground::IngressJobs.lookup_cron(params[:name])
    return render(json: { error: "unknown cron job" }, status: :not_found) unless job

    run_job(job, channel: "cron")
  end

  def webhook
    job = Master::Ground::IngressJobs.lookup_webhook(params[:name])
    return render(json: { error: "unknown webhook" }, status: :not_found) unless job

    run_job(job, channel: "webhook")
  end

  private

  def run_job(job, channel:)
    body = parse_body
    message = body[:message].presence || job["message"].to_s
    return render(json: { error: "empty message" }, status: :bad_request) if message.empty?

    elevated = job["elevated"] == true
    metadata = {
      ingress_channel: channel,
      ingress_job: job["name"],
      trust: elevated ? :owner : :untrusted,
    }

    result = Master::Reach::IngressRunner.run_turn(
      container: container,
      message: message,
      metadata: metadata,
      elevated: elevated
    )
    render json: ingress_response(result, metadata)
  rescue StandardError => e
    render json: { error: e.message, ok: false }, status: :internal_server_error
  end

  def parse_body
    raw = request.request_parameters.presence
    if raw.nil? || raw.empty?
      raw = JSON.parse(request.body.read) if request.content_type.to_s.include?("json")
    end
    Master::Reach::OpenclawBridge.parse_body(raw || {})
  rescue JSON::ParserError
    {}
  end

  def ingress_response(result, metadata)
    agent = container[:agent]
    value = result.ok? ? result.value! : nil
    output = if value.is_a?(Hash)
               value[:rendered] || value[:output] || value.to_s
             else
               value || result.message
             end
    {
      ok: result.ok?,
      output: output.to_s,
      model: agent&.model.to_s,
      job: metadata[:ingress_job],
      channel: metadata[:ingress_channel],
    }
  end

  def require_ingress_token!
    header = request.headers["Authorization"].to_s
    token = header.sub(/\ABearer\s+/i, "").strip
    return if MasterIngressToken.valid?(token)

    render json: { error: "ingress auth required" }, status: :unauthorized
  end

  def enforce_ingress_rate_limit
    enforce_rate_limit!("master:rl:ingress:#{request.remote_ip}", limit: INGRESS_RATE_LIMIT, window: INGRESS_WINDOW_S)
  end
end