# frozen_string_literal: true

class SecurityAdvisoryRefreshJob < ApplicationJob
  queue_as :bulk

  BATCH_SIZE = 50
  CURSOR_KEY = "bsdports:advisory_refresh_cursor"

  # No sleep between ports.
  #
  # It was six seconds, and fifty ports meant the job held the bulk queue for
  # five minutes on a box with one core and a gigabyte of memory. The sleep was
  # standing in for rate limiting, and rate limiting belongs where the request
  # is made: NvdCve owns the NVD budget, and concurrency belongs to the queue.
  #
  # The wrap is bounded too. When the cursor ran past the last id the batch came
  # back empty and the job restarted from the first row, forever, so it never
  # idled — it just kept re-reading the same fifty ports at whatever interval it
  # was scheduled. One lap is the recycle; a second lap in the same run is a
  # loop, so the cursor resets and the job returns.
  def perform(batch_size: BATCH_SIZE)
    cursor = Rails.cache.read(CURSOR_KEY).to_i
    ports = Port.where(id: (cursor + 1)..).order(:id).limit(batch_size).to_a
    if ports.empty?
      Rails.cache.delete(CURSOR_KEY)
      Rails.logger.info("bsdports: advisory refresh reached the last port; cursor reset")
      return
    end

    refreshed = 0
    ports.each do |port|
      refreshed += NvdCve.crossref(port, limit: 3).size
    rescue StandardError => e
      Rails.logger.warn("bsdports: advisory refresh skipped for #{port.name}: #{e.message}")
    end

    Rails.cache.write(CURSOR_KEY, ports.last.id, expires_in: 2.days)
    Rails.logger.info("bsdports: refreshed #{refreshed} security advisories across #{ports.size} ports")
  end
end
