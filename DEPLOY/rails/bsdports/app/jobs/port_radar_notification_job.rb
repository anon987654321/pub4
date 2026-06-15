# frozen_string_literal: true

class PortRadarNotificationJob < ApplicationJob
  queue_as :default

  def perform
    Watch.includes(:user, :port).find_each do |watch|
      port = watch.port
      recent = port.port_updates.where("committed_at >= ?", 24.hours.ago)
      next if recent.empty?

      Shared::EventEmitter.call(
        "bsdports.port_radar",
        user_id: watch.user_id,
        port_id: port.id,
        updates: recent.pluck(:new_version)
      ) if defined?(Shared::EventEmitter)
    end
  end
end