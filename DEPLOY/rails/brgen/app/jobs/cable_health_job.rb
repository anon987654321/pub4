# frozen_string_literal: true

require_relative "../../../shared/app/services/shared/cable_health"

class CableHealthJob < ApplicationJob
  queue_as :bulk

  MAX_CONNECTIONS = Shared::CableHealth::ALERT_THRESHOLD

  def perform
    count = Shared::CableHealth.connection_count
    return unless Shared::CableHealth.alert?(connection_count: count, max_connections: MAX_CONNECTIONS)

    message = Shared::CableHealth.message(app: "brgen", connection_count: count, max_connections: MAX_CONNECTIONS)
    Rails.logger.warn(message)
    Shared::EventEmitter.call("brgen.cable.health", message:, connection_count: count, max_connections: MAX_CONNECTIONS) if defined?(Shared::EventEmitter)
  end
end
