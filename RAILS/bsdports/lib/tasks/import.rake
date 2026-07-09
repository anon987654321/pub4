# frozen_string_literal: true

namespace :ports do
  desc "Queue OpenBSD ports tree import (platform=openbsd tree_path=...)"
  task import: :environment do
    PortsImportJob.perform_later(
      platform_slug: ENV.fetch("PLATFORM", "openbsd"),
      tree_path: ENV["BSDPORTS_TREE_PATH"],
      use_ftp_fallback: ENV.fetch("FTP_FALLBACK", "true") == "true"
    )
    puts "Queued ports import platform=#{ENV.fetch('PLATFORM', 'openbsd')}"
  end

  desc "Run ports tree import synchronously (platform=openbsd tree_path=...)"
  task import_now: :environment do
    platform = Platform.find_by!(slug: ENV.fetch("PLATFORM", "openbsd"))
    result = Ports::Importer.call(
      platform:,
      tree_path: ENV["BSDPORTS_TREE_PATH"],
      use_ftp_fallback: ENV.fetch("FTP_FALLBACK", "true") == "true"
    )
    puts "Imported #{result.ports_count} ports from #{result.tree_path}"
  end
end