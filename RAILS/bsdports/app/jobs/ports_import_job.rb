# frozen_string_literal: true

class PortsImportJob < ApplicationJob
  queue_as :bulk

  def perform(platform_slug: "openbsd", tree_path: nil, use_ftp_fallback: true)
    platform = Platform.find_by!(slug: platform_slug)
    Shared::EventEmitter.call("bsdports.import.started", platform: platform.slug, tree_path:) if defined?(Shared::EventEmitter)
    Rails.logger.info("bsdports import started platform=#{platform.slug} tree_path=#{tree_path}")

    result = Ports::Importer.call(platform:, tree_path:, use_ftp_fallback:)
    Shared::EventEmitter.call(
      "bsdports.import.finished",
      platform: platform.slug,
      ports_count: result.ports_count,
      tree_path: result.tree_path
    ) if defined?(Shared::EventEmitter)
  rescue StandardError => e
    Shared::EventEmitter.call("bsdports.import.failed", platform: platform_slug, error: e.message) if defined?(Shared::EventEmitter)
    raise
  end
end
