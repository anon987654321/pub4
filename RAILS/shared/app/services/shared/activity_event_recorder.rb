# frozen_string_literal: true

module Shared
  class ActivityEventRecorder
    def self.call(actor:, event_name:, object:, source_vertical:, locality: nil, visibility: "public", metadata: {})
      return unless defined?(::ActivityEvent)

      ::ActivityEvent.create!(
        actor:,
        event_name:,
        object_type: object.class.name,
        object_id: object.id,
        source_vertical:,
        locality:,
        visibility:,
        metadata:,
      )
    end
  end
end
