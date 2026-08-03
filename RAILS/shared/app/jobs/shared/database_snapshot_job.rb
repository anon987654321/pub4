# frozen_string_literal: true

require "fileutils"

module Shared
  # Point-in-time backup of the primary database, using SQLite's own VACUUM INTO
  # (a consistent, defragmented copy that doesn't lock writers out). Gzips the
  # copy and keeps the last KEEP snapshots. This is the stopgap that runs while
  # litestream is uninstalled/unconfigured — real, restorable backups of the
  # irreplaceable user data with no extra binary or credentials.
  #
  # Same-disk by default (accidental-delete / corruption / bad-migration recovery,
  # NOT disk-failure DR). Point PUB4_BACKUP_DIR at an off-host mount, or copy the
  # snapshots off the box, for true disaster recovery.
  class DatabaseSnapshotJob < ApplicationJob
    queue_as :bulk
    KEEP = 7

    def perform
      dir = backup_dir
      FileUtils.mkdir_p(dir)
      stamp = Time.current.utc.strftime("%Y%m%d-%H%M%S")
      target = File.join(dir, "production-#{stamp}.sqlite3")

      connection = ActiveRecord::Base.connection
      connection.execute("VACUUM INTO #{connection.quote(target)}")
      system("gzip", "-f", target)

      rotate(dir)
      "#{target}.gz"
    end

    private

    def backup_dir
      ENV["PUB4_BACKUP_DIR"].presence || Rails.root.join("..", "backups").to_s
    end

    def rotate(dir)
      snapshots = Dir.glob(File.join(dir, "production-*.sqlite3.gz")).sort
      snapshots[0...-KEEP].to_a.each { |old| File.delete(old) rescue nil }
    end
  end
end
