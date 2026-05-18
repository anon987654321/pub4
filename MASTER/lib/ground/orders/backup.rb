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
    SSH_OPTS    = %w[-o BatchMode=yes -o ConnectTimeout=10].freeze

    def call
      src = File.expand_path("../../..", root)  # ~/pub4 from MASTER root
      cmd = ["openrsync", "-ae", "ssh #{SSH_OPTS.join(" ")}",
             src, "#{REMOTE_HOST}:#{REMOTE_PATH}"]
      out, status = Open3.capture2e(*cmd)
      if status.success?
        bus&.publish("backup:ok", bytes: File.size(src) rescue nil)
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
