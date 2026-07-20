# frozen_string_literal: true

class SecurityAdvisoryRefreshJob < ApplicationJob
  queue_as :bulk

  BATCH_SIZE = 50
  CURSOR_KEY = "bsdports:advisory_refresh_cursor"
  SLEEP_SECONDS = 6

  def perform(batch_size: BATCH_SIZE)
    refreshed = 0
    cursor = Rails.cache.read(CURSOR_KEY).to_i
    ports = Port.where("id > ?", cursor).order(:id).limit(batch_size).to_a
    ports = Port.order(:id).limit(batch_size).to_a if ports.empty?

    ports.each_with_index do |port, index|
      advisories = NvdCve.crossref(port, limit: 3)
      refreshed += advisories.size
      sleep(SLEEP_SECONDS) if index < ports.length - 1
    rescue StandardError => e
      Rails.logger.warn("bsdports: advisory refresh skipped for #{port.name}: #{e.message}")
    end

    Rails.cache.write(CURSOR_KEY, ports.last.id, expires_in: 2.days) if ports.any?
    Rails.logger.info("bsdports: refreshed #{refreshed} security advisories across #{ports.size} ports")
  end
end
