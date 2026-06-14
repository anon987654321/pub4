# frozen_string_literal: true

# DRY + KISS: centralize activity event recording boilerplate.
# Replaces repeated "return unless defined?(ActivityEventRecorder); ActivityEventRecorder.call(...)"
# Include in models (preferred) or controllers. Uses the brgen service when present.
module Shared
  module ActivityTrackable
    extend ActiveSupport::Concern

    class_methods do
      def record_activity!(event_name, **opts)
        _record_activity_impl(event_name, **opts)
      end

      private

      def _record_activity_impl(event_name, **opts)
        recorder = if defined?(ActivityEventRecorder)
                     ActivityEventRecorder
                   elsif defined?(Shared::ActivityEventRecorder)
                     Shared::ActivityEventRecorder
                   end
        return unless recorder

        actor = opts[:actor] || try(:user) || (defined?(Current) && Current.try(:user))
        recorder.call(
          actor: actor,
          event_name: event_name,
          object: opts[:object] || self,
          source_vertical: opts[:source_vertical] || "general",
          locality: opts[:locality],
          visibility: opts[:visibility] || "public",
          metadata: opts[:metadata] || {}
        )
      rescue => e
        Rails.logger&.warn("Activity record skipped: #{e.class}: #{e.message}") if defined?(Rails)
      end
    end

    # Instance form delegates to class for convenience
    def record_activity!(event_name, **opts)
      self.class.record_activity!(event_name, **{ object: self }.merge(opts))
    end
  end
end
