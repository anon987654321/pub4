# frozen_string_literal: true

class HealthController < ActionController::API
  def show
    checks = {
      tts: tts_healthy?,
      replicate: replicate_healthy?,
      git: git_healthy?,
      container: container_healthy?,
    }
    critical = %i[tts git]
    critical_ok = critical.all? { |key| checks[key] }
    status = critical_ok ? (checks.values.all? ? "ok" : "degraded") : "unavailable"
    http = critical_ok ? :ok : :service_unavailable
    render json: { status:, checks: }, status: http
  end

  private

  def tts_healthy?
    Master::Voice::Speech.available? || Master::Voice::Transcendent.enabled?
  rescue StandardError
    false
  end

  def replicate_healthy?
    Master::Voice::Engines.replicate_token?
  rescue StandardError
    false
  end

  def git_healthy?
    repo = Rails.root.join("..").to_s
    system("git", "-C", repo, "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL)
  rescue StandardError
    false
  end

  def container_healthy?
    c = Rails.application.config.x.master_container
    return "warming" unless c

    c[:agent].respond_to?(:model)
  rescue StandardError
    false
  end
end