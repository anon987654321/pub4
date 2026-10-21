# frozen_string_literal: true

class NvdCveCrossrefJob < ApplicationJob
  queue_as :bulk

  def perform(port_id:)
    port = Port.find_by(id: port_id)
    return unless port

    if (allowed_at = NvdRateLimit.claim_or_defer)
      self.class.set(wait_until: allowed_at).perform_later(port_id:)
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
end
