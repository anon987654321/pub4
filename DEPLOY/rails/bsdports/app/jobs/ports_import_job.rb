# frozen_string_literal: true

class PortsImportJob < ApplicationJob
  queue_as :imports

  def perform(source: nil)
    Shared::EventEmitter.call("bsdports.import.started", source:) if defined?(Shared::EventEmitter)
    Rails.logger.info("bsdports import started source=#{source}")

    count = PortsFtpImportService.call
    Rails.logger.info("bsdports import upserted #{count} ports from FTP/demo index")

    Shared::EventEmitter.call("bsdports.import.finished", source:) if defined?(Shared::EventEmitter)
  rescue StandardError => e
    Shared::EventEmitter.call("bsdports.import.failed", source:, error: e.message) if defined?(Shared::EventEmitter)
    raise
  end
end
