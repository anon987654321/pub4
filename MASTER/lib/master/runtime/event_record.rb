# frozen_string_literal: true

require "securerandom"
require "time"

module Master
  module Runtime
    EventRecord = Struct.new(:id, :timestamp, :workflow_id, :event, :payload, keyword_init: true) do
      def self.build(event:, workflow_id: nil, payload: {})
        now = Time.now.utc
        new(
          id: SecureRandom.uuid,
          timestamp: now.iso8601(6),
          workflow_id: workflow_id,
          event: event.to_s,
          payload: payload || {}
        )
      end

      def to_h
        {
          id: id,
          timestamp: timestamp,
          workflow_id: workflow_id,
          event: event,
          payload: payload
        }.compact
      end
    end
  end
end
