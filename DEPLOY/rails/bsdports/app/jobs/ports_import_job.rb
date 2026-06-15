# frozen_string_literal: true

class PortsImportJob < ApplicationJob
  queue_as :imports

  def perform(source: nil)
    Shared::EventEmitter.call("bsdports.import.started", source:) if defined?(Shared::EventEmitter)
    Rails.logger.info("bsdports import started source=#{source}")

    # Nightly sync demo (real: fetch CVS/git ports tree, parse Makefiles, upsert)
    cat = Category.find_or_create_by(name: "demo") { |c| c.description = "nightly demo category" }
    p = Port.find_or_create_by(pkgpath: "demo/nightly") do |pp|
      pp.name = "nightly-demo"
      pp.version = "1.0"
      pp.category = cat
      pp.comment = "demo from nightly job"
    end
    p.port_updates.find_or_create_by(new_version: p.version) do |u|
      u.old_version = "0.9"
      u.commit_message = "nightly sync demo"
    end

    Shared::EventEmitter.call("bsdports.import.finished", source:) if defined?(Shared::EventEmitter)
  rescue StandardError => e
    Shared::EventEmitter.call("bsdports.import.failed", source:, error: e.message) if defined?(Shared::EventEmitter)
    raise
  end
end
