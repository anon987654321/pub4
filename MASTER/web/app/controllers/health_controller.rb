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
# TTS is mandatory, so it stays critical — a genuine TTS-capability
# outage (worker missing or EventMachine without SSL) should 503 and alert.
# replicate (media) stays non-critical (degraded). tts_healthy? now checks
# capability rather than transient socket liveness, so this no longer
# false-503s while the on-demand daemon is between syntheses.
#
# git is NOT critical, and was. It answers "can this process read the SHA it
# is running", which is provenance rather than liveness: a service that
# cannot name its own commit still serves every request correctly. Making it
# critical meant one unreadable repo took ai.brgen.no to a hard 503 —
# measured live 2026-08-26 with tts: true and git: false, so the only failing
# check was the one that cannot affect a response.
#
# It failed for a reason worth keeping next to the decision. 37bfa28ce moved
# the daemon off `dev` (whose doas rule is nopass and uncommented, so any
# code execution as dev was root) onto its own `master` user. The repo at
# /home/dev/pub4 still belongs to dev, and git refuses to operate on another
# user's repository — "detected dubious ownership" — so every git call from
# the daemon started failing silently. cbd97c2b0 already caught one
# consequence of that same move; this is the second.
    critical = %i[tts]
    critical_ok = critical.all? { |key| checks[key] }
    status = if critical_ok
               checks.values.all? { |value| value == true } ? "ok" : "degraded"
             else
               "unavailable"
             end
    http = critical_ok ? :ok : :service_unavailable
    render json: { status:, checks:, deploy: deploy_confidence }, status: http
  end

  private

  def tts_healthy?
    return true if Rails.env.test?

    # Capability check, not socket liveness. The worker + EventMachine-with-SSL
    # are what make synthesis possible; the daemon socket is spun up on
    # demand (and can be reaped under load on the 1-vCPU host), so requiring a
    # live socket here produced a false negative — tts reported down between
    # syntheses while synthesis worked fine, 503'ing /health.
    Master::Voice::Speech.edge_tts_available?
  rescue StandardError => _
    false
  end

  def replicate_healthy?
    Master::Voice::Engines.replicate_token?
  rescue StandardError => _
    false
  end

  # -c safe.directory, because the daemon and the repository have different
  # owners by design: the process runs as `master` and /home/dev/pub4 belongs to
  # `dev`. Passing it per call keeps the fix in the thing that needs it rather
  # than in a global git config on the box, which nothing in this repo
  # provisions and which a rebuild would lose.
  def git_healthy?
    repo = Rails.root.join("..").to_s
    system("git", "-c", "safe.directory=#{repo}", "-C", repo, "rev-parse", "--is-inside-work-tree",
           out: File::NULL, err: File::NULL)
  rescue StandardError => _
    false
  end

  def container_healthy?
    c = Rails.application.config.x.master_container
    return false unless c

    c[:agent].respond_to?(:model)
  rescue StandardError => _
    false
  end

  def deploy_confidence
    {
      git_sha:,
      voice_policy: Master::Voice::Policy.browser_payload,
      tts_socket: tts_socket_alive?,
      face_runtime_digest:,
      assets_precompile_at: assets_precompile_stamp,
    }
  rescue StandardError => e
    { error: e.message }
  end

  def git_sha
    repo = Rails.root.join("..").to_s
    out, status = Open3.capture2("git", "-c", "safe.directory=#{repo}", "-C", repo,
                                 "rev-parse", "--short", "HEAD")
    status.success? ? out.strip : nil
  end

  def tts_socket_alive?
    size = Master::Voice::TtsSupervisor.pool_size
    size.times.any? do |i|
      Master::Voice::TtsSupervisor.socket_alive?(Master::Voice::TtsSupervisor.socket_path(index: i))
    end
  rescue StandardError => _
    false
  end

  def face_runtime_digest
    manifest = Rails.root.join("public", "assets", ".manifest.json")
    return unless File.file?(manifest)

    data = JSON.parse(File.read(manifest))
    entry = data["face.runtime.js"]
    digested = entry.is_a?(Hash) ? entry["digested_path"].to_s : ""
    digested.empty? ? nil : digested.sub(%r{\Aassets/}, "")
  rescue StandardError # scan: intentional — the health payload omits what it cannot read; absence is the report
    nil
  end

  def assets_precompile_stamp
    stamp = Rails.root.join("tmp", ".assets_precompile_stamp")
    File.mtime(stamp).utc.iso8601 if File.file?(stamp)
  rescue StandardError # scan: intentional — the health payload omits what it cannot read; absence is the report
    nil
  end
end
