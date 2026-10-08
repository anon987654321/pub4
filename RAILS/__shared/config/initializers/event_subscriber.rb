# frozen_string_literal: true

module Shared
  class EventLogSubscriber
    def emit(event)
      payload = event[:payload].map { |key, value| "#{key}=#{value}" }.join(" ")
      source = event[:source_location]
      location = source ? " at #{source[:filepath]}:#{source[:lineno]}" : ""
      Rails.logger.info("[#{event[:name]}] #{payload}#{location}")
    end
  end
end

Rails.application.config.after_initialize do
  next unless defined?(Rails.event)

  Rails.event.subscribe(Shared::EventLogSubscriber.new)
end
