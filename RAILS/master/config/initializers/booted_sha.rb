# frozen_string_literal: true

require "open3"

# The commit this process booted, read once at boot. A `git pull` on vm23 moves
# HEAD without restarting Falcon, so /health reading HEAD per request named code
# the process was not running — and deploy.git_sha exists to answer exactly that.
#
# -c safe.directory because the daemon runs as `master` and the checkout belongs
# to `dev`; HealthController#git_healthy? carries the same flag for the same reason.
Rails.application.config.x.booted_sha = begin
  repo = Master::REPO_ROOT
  out, status = Open3.capture2("git", "-c", "safe.directory=#{repo}", "-C", repo,
                               "rev-parse", "--short", "HEAD", err: File::NULL)
  status.success? ? out.strip.freeze : nil
rescue SystemCallError # scan: intentional — no git binary means no provenance, and /health reports null
  nil
end

# The asset and service-worker cache generation: rc.d exports CACHE_VERSION from
# the deployed HEAD, and a process started without it uses the commit it booted,
# so a new deploy still names a new cache instead of every build sharing "v2".
Rails.application.config.x.cache_version =
  ENV["CACHE_VERSION"].presence || Rails.application.config.x.booted_sha || "dev"
