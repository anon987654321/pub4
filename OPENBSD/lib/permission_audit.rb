# frozen_string_literal: true

module Deploy
  # Secrets and app data that anyone on the box can read, and daemon logs the
  # daemon cannot write.
  #
  # Both have happened. The app homes were world-readable until 2026-08-25, with
  # production databases inside them. And `.master/tts-worker-0.log` came back
  # `root:master` while the daemon runs as `master`: it could not open its own
  # log, died before creating a socket, and /health read tts true while no
  # socket existed. OPERATOR.sh and vps_ci.sh set the modes; nothing checked
  # they stayed set.
  #
  # The policy is what those scripts write: `/etc/<app>.env` root:<app> 0640,
  # `/home/<app>/app/storage` 0750. So the rule is "no permission for other" on
  # both, not an exact mode, which leaves the group bits to the scripts that own
  # them. Stats are injected so the rule is decidable off the box.
  module PermissionAudit
    module_function

    # entries: [{ path:, mode:, owner: }] — mode as File::Stat#mode, owner as a
    # user name. Returns failure lines.
    def failures(secrets:, private_dirs:, daemon_logs:, daemon_user:)
      lines = []
      (secrets + private_dirs).each do |entry|
        next unless entry[:mode].to_i.anybits?(0o007)

        lines << format("permissions: %<path>s is %<mode>04o — other can reach it", path: entry[:path],
                                                                                    mode: entry[:mode] & 0o7777)
      end
      daemon_logs.each do |entry|
        next if entry[:owner] == daemon_user

        lines << "permissions: #{entry[:path]} is owned by #{entry[:owner]}, and #{daemon_user} writes it"
      end
      lines
    end
  end
end
