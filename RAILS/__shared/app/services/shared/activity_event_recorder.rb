# frozen_string_literal: true

module Shared
  class ActivityEventRecorder
    # `subject:`, matching Shared::DomainEvent's payload and the columns since
    # 20260825122000. The keyword and the column were `object` on this side
    # only, so this class was translating between two names for one thing.
    def self.call(actor:, event_name:, subject:, source_vertical:, locality: nil, visibility: "public", metadata: {})
      return unless defined?(::ActivityEvent)

      ::ActivityEvent.create!(
        actor:,
        event_name:,
        subject_type: subject.class.name,
        subject_id: subject.id,
        source_vertical:,
        locality:,
        visibility:,
        metadata:,
      )
    end
  end
end
