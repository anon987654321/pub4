# frozen_string_literal: true

module Shared
  module ActivityTrackable
    extend ActiveSupport::Concern

    class_methods do
      # tracks_activity created: "PostCreated", source_vertical: "social"
      def tracks_activity(created: nil, updated: nil, source_vertical: "general", visibility: "public", actor: nil)
        if created
          after_commit on: :create do
            act = actor ? public_send(actor) : activity_actor
            record_activity!(created, actor: act, source_vertical: source_vertical, visibility: visibility)
          end
        end
        if updated
          after_commit on: :update do
            act = actor ? public_send(actor) : activity_actor
            record_activity!(updated, actor: act, source_vertical: source_vertical, visibility: visibility)
          end
        end
      end
    end

    def record_activity!(event_name, **opts)
      action = opts[:action] || event_name.to_s.tr(":", ".").underscore.tr("_", ".")
      Shared::DomainEvent.record!(
        actor: opts[:actor] || activity_actor,
        action: action,
        subject: opts[:object] || self,
        source_vertical: opts[:source_vertical] || "general",
        locality: opts[:locality],
        visibility: opts[:visibility] || "public",
        metadata: (opts[:metadata] || {}).merge(legacy_event_name: event_name.to_s)
      )
    rescue StandardError => e
      Rails.logger.warn("activity skipped: #{e.class}: #{e.message}") if defined?(Rails)
    end

    private

    def activity_actor
      if respond_to?(:user) && user.present?
        user
      elsif defined?(Current) && Current.respond_to?(:user)
        Current.user
      end
    end
  end
end