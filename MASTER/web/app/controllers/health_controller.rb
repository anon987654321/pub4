# frozen_string_literal: true

require "open3"

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
    render json: { status:, checks:, deploy: deploy_confidence }, status: http
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

  def deploy_confidence
    {
      git_sha: git_sha,
      voice_policy: Master::Voice::Policy.browser_payload,
      tts_socket: tts_socket_alive?,
      face_runtime_digest: face_runtime_digest,
      assets_precompile_at: assets_precompile_stamp,
    }
  rescue StandardError => e
    { error: e.message }
  end

  def git_sha
    repo = Rails.root.join("..").to_s
    out, status = Open3.capture2("git", "-C", repo, "rev-parse", "--short", "HEAD")
    status.success? ? out.strip : nil
  end

  def tts_socket_alive?
    Master::Voice::TtsSupervisor.pool_size.times.any? do |i|
      Master::Voice::TtsSupervisor.socket_alive?(Master::Voice::TtsSupervisor.socket_path(index: i))
    end
  rescue StandardError
    false
  end

  def face_runtime_digest
    manifest = Rails.root.join("public", "assets", ".manifest.json")
    return nil unless File.file?(manifest)

    data = JSON.parse(File.read(manifest))
    entry = data["face.runtime.js"]
    digested = entry.is_a?(Hash) ? entry["digested_path"].to_s : ""
    digested.empty? ? nil : digested.sub(%r{\Aassets/}, "")
  rescue StandardError
    nil
  end

  def assets_precompile_stamp
    stamp = Rails.root.join("tmp", ".assets_precompile_stamp")
    File.mtime(stamp).utc.iso8601 if File.file?(stamp)
  rescue StandardError
    nil
  end
end