# frozen_string_literal: true

require "json"

# Webhook + cron ingress: scheduled/external triggers into MASTER TurnRouter.
# Auth: Authorization: Bearer <MASTER_INGRESS_TOKEN>
class IngressController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_container!, only: :health
  before_action :require_ingress_token!, except: :health
  before_action :enforce_ingress_rate_limit, except: :health

  # data/security.yml carried ingress.rate_limit_per_minute: 30 with no
  # reader while these two constants carried the same numbers — a policy file and
  # its subject able to disagree without anything noticing. The file is the source
  # now; the literals stay as the fallback for a checkout without it.
  DEFAULT_RATE_LIMIT = 30
  DEFAULT_WINDOW_S = 60

  def self.security_defaults
    Master.load_yaml(Master.data_path("security.yml")) || {}
  rescue StandardError => e
    # An unreadable security.yml silently becoming {} is fail-open — the one
    # place a swallow must at least be on the record.
    Master::Ground::Swallow.log(e, context: "Ingress.security_defaults", severity: :load_bearing)
    {}
  end

  def self.rate_limit
    Integer(security_defaults.dig("ingress", "rate_limit_per_minute") || DEFAULT_RATE_LIMIT)
  end

  def self.rate_window_seconds
    Integer(security_defaults.dig("ingress", "window_seconds") || DEFAULT_WINDOW_S)
  end

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

    result = Master::Io::IngressRunner.run_turn(
      container:,
      message:,
      metadata:,
      elevated:,
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
    deep_symbolize(raw.is_a?(Hash) ? raw : {})
  rescue JSON::ParserError
    {}
  end

  def deep_symbolize(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(key, value), out| out[key.to_sym] = deep_symbolize(value) }
    when Array
      obj.map { |item| deep_symbolize(item) }
    else
      obj
    end
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
    enforce_rate_limit!(
      "master:rl:ingress:#{request.remote_ip}",
      limit: self.class.rate_limit,
      window: self.class.rate_window_seconds
    )
  end
end
