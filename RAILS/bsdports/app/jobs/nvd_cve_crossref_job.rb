# frozen_string_literal: true

require "time"

class NvdCveCrossrefJob < ApplicationJob
  queue_as :bulk

  def self.enqueue_for(port_id:)
    reserve_and_enqueue(port_id:, slot_at: NvdRateLimit.reserve_slot)
  end

  def perform(port_id:, slot_at:)
    port = Port.find_by(id: port_id)
    return unless port

    scheduled_at = Time.iso8601(slot_at.to_s)
    now = Time.current

    if now < scheduled_at
      self.class.reserve_and_enqueue(port_id:, slot_at: scheduled_at)
      return
    end

    # A drained or delayed queue may run many expired reservations together.
    # Re-reserve stale jobs in order; only the first gets an immediate slot.
    if now >= scheduled_at + NvdRateLimit.interval
      scheduled_at = NvdRateLimit.reserve_slot
      if scheduled_at > Time.current
        self.class.reserve_and_enqueue(port_id:, slot_at: scheduled_at)
        return
      end
    end

    if (allowed_at = NvdRateLimit.claim_or_defer)
      self.class.reserve_and_enqueue(port_id:, slot_at: allowed_at)
      return
    end

    result = NvdCve.crossref(port)
    action = result.status == :succeeded ? "PortCvesCrossreferenced" : "PortCvesCrossrefFailed"
    port.record_activity!(
      action,
      source_vertical: "bsdports",
      metadata: { status: result.status.to_s, advisory_count: result.count, error: result.error }
    )
  end

  def self.reserve_and_enqueue(port_id:, slot_at:)
    set(wait_until: slot_at).perform_later(port_id:, slot_at: slot_at.iso8601(6))
  end
end
