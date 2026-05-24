# frozen_string_literal: true

class PortsImportJob < ApplicationJob
  queue_as :imports

  def perform(source: nil)
    Shared::EventEmitter.call("bsdports.import.started", source:) if defined?(Shared::EventEmitter)
    Rails.logger.info("bsdports import started source=#{source}")

    # Hook real FTP/git ports-tree import here. Keep the job idempotent:
    # parse source -> upsert Platform/Category/Port -> upsert Dependency rows.

    Shared::EventEmitter.call("bsdports.import.finished", source:) if defined?(Shared::EventEmitter)
  rescue StandardError => e
    Shared::EventEmitter.call("bsdports.import.failed", source:, error: e.message) if defined?(Shared::EventEmitter)
    raise
  end
end
