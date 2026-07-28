# frozen_string_literal: true

module Master
  module Ground
    module Orders
    # Backup — openrsync standing order.
    # Syncs ~/pub4 to wingman1.openbsd.amsterdam:backup using openrsync over SSH.
    # Runs as a background standing order; never blocks the main loop.
      class Backup < Base
        REMOTE_HOST = "s4vm23@wingman1.openbsd.amsterdam"
        REMOTE_PATH = "backup"
        SSH_OPTS = %w[-o BatchMode=yes -o ConnectTimeout=10].freeze

        # The repo root is one level above MASTER. This was "../../..", which
        # climbed three and landed outside the checkout entirely (/home on the
        # VPS), so the order would have rsynced the wrong tree to the remote.
        # Named so the path is assertable without executing the sync.
        def source_root = File.expand_path("..", root)

        def call
          src = source_root
          return Result.err("backup: #{src} is not a directory", category: :infrastructure) unless File.directory?(src)

          cmd = ["openrsync", "-ae", "ssh #{SSH_OPTS.join(" ")}",
                 src, "#{REMOTE_HOST}:#{REMOTE_PATH}"]
          out, status = Master::Io::Exec.capture2e(*cmd)
          if status.success?
            bus&.publish("backup:ok", src:)
            Result.ok("backup: synced #{File.basename(src)} → #{REMOTE_HOST}")
          else
            bus&.publish("backup:error", error: out.lines.last.to_s.strip)
            Result.err("backup: #{out.lines.last.to_s.strip}", category: :infrastructure)
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Orders::Backup.call", event_bus: bus)
          Result.err(e.message, category: :infrastructure)
        end
      end
    end
  end
end
