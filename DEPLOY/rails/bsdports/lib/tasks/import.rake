# frozen_string_literal: true

namespace :ports do
  desc "Import OpenBSD ports metadata"
  task import: :environment do
    PortsImportJob.perform_later
    puts "Queued OpenBSD ports import"
  end
end
