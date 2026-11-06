# frozen_string_literal: true

class SecurityAdvisoryRefreshJob < ApplicationJob
  queue_as :bulk

  # Two runs would share one cursor and one NVD budget.
  limits_concurrency to: 1, key: "advisory-refresh", duration: 1.hour, on_conflict: :discard

  BATCH_SIZE = 50
  CURSOR_KEY = "bsdports:advisory_refresh_cursor"

  # This cursor job only enqueues a bounded batch. Each per-port job reserves a
  # distinct shared NVD slot and checks actual request spacing again at execution,
  # including after a delayed queue drain. No request thread or worker sleeps.
  #
  # The wrap is bounded too. When the cursor ran past the last id the batch came
  # back empty and the job restarted from the first row, forever, so it never
  # idled — it kept re-reading the same fifty ports at whatever interval it
  # was scheduled. One lap is the recycle; a second lap in the same run is a
  # loop, so the cursor resets and the job returns.
  def perform(batch_size: BATCH_SIZE)
    platform = Platform.active.find_by!(slug: "openbsd")
    cursor = Rails.cache.read(CURSOR_KEY).to_i
    ports = platform.ports.where(id: (cursor + 1)..).order(:id).limit(batch_size).to_a
    if ports.empty?
      Rails.cache.delete(CURSOR_KEY)
      Rails.logger.info("bsdports: advisory refresh reached the last port; cursor reset")
      return
    end

    enqueued = 0
    cursor_after_batch = cursor
    ports.each do |port|
      NvdCveCrossrefJob.enqueue_for(port_id: port.id)
      enqueued += 1
      cursor_after_batch = port.id
    rescue StandardError => e
      Rails.logger.error("bsdports: advisory refresh stopped at #{port.name}: #{e.class}: #{e.message}")
      break
    end

    Rails.cache.write(CURSOR_KEY, cursor_after_batch, expires_in: 2.days) if cursor_after_batch > cursor
    Rails.logger.info("bsdports: queued #{enqueued} NVD cross-references across #{ports.size} selected ports")
  end
end
