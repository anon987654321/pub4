# frozen_string_literal: true

module Shared
  class DomainEvent
    def self.record!(actor:, action:, subject:, source_vertical: nil, locality: nil, visibility: "public", metadata: {})
      app = Rails.application.class.module_parent_name.to_s.downcase
      vertical = source_vertical.presence || app
      payload = {
        actor_id: actor&.id,
        action: action.to_s,
        subject_type: subject.class.name,
        subject_id: subject.id,
        app:,
        source_vertical: vertical,
        locality:,
        visibility:,
      }.merge(metadata || {})

      EventEmitter.call("#{app}.#{action}", **payload)
      persist_activity!(actor:, action:, subject:, vertical:, locality:, visibility:, metadata: metadata || {})
      true
    rescue StandardError => e
      Rails.logger.warn("domain_event skipped: #{e.class}: #{e.message}") if defined?(Rails)
      false
    end

    def self.persist_activity!(actor:, action:, subject:, vertical:, locality:, visibility:, metadata:)
      return unless defined?(::ActivityEvent)

      ActivityEventRecorder.call(
        actor:,
        event_name: action_to_event_name(action),
        subject:,
        source_vertical: vertical,
        locality:,
        visibility:,
        metadata: metadata.merge(domain_action: action.to_s),
      )
    end

    def self.action_to_event_name(action)
      action.to_s.split(".").map(&:camelize).join
    end

    private_class_method :persist_activity!, :action_to_event_name
  end
end
