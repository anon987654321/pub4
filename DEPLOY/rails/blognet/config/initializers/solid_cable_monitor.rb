# frozen_string_literal: true
# AN307: Solid Cable connection tracking

Rails.application.config.after_initialize do
  next unless defined?(ActionCable)

  Thread.new do
    loop do
      sleep 60
      count = ActionCable.server.connections.size
      Rails.logger.warn("[solid_cable] #{count} concurrent connections") if count > 1000
    rescue StandardError => e
      Rails.logger.debug("[solid_cable] monitor: #{e.message}")
    end
  end
end