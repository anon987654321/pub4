# frozen_string_literal: true

module Shared
  module ActivityTrackable
    extend ActiveSupport::Concern

    class_methods do
      # tracks_activity created: "PostCreated", source_vertical: "social"
      def tracks_activity(created: nil, updated: nil, source_vertical: "general", visibility: "public", actor: nil)
        if created
          after_commit on: :create do
            record_activity!(created, actor: resolved_activity_actor(actor), source_vertical:,
visibility:)
          end
        end
        if updated
          after_commit on: :update do
            record_activity!(updated, actor: resolved_activity_actor(actor), source_vertical:,
visibility:)
          end
        end
      end
    end

    def record_activity!(event_name, **opts)
      action = opts[:action] || event_name.to_s.tr(":", ".").underscore.tr("_", ".")
      Shared::DomainEvent.record!(
        actor: opts[:actor] || activity_actor,
        action:,
        subject: opts[:object] || self,
        source_vertical: opts[:source_vertical] || "general",
        locality: opts[:locality],
        visibility: opts[:visibility] || "public",
        metadata: (opts[:metadata] || {}).merge(legacy_event_name: event_name.to_s),
      )
    rescue StandardError => e
      Rails.logger.warn("activity skipped: #{e.class}: #{e.message}") if defined?(Rails)
    end

    private

    # The actor is nearly always a belongs_to (`actor: :user`, `:buyer`,
    # `:sender`, …). Reading it with a bare public_send inside an after_commit is
    # a lazy association read, and strict_loading_by_default is true in every
    # environment with production raising rather than logging. So emitting an
    # activity event for any record that was loaded from the database — which is
    # every controller update action — raised *after* the write had committed.
    #
    # record_activity! already swallows its own failures ("activity skipped"),
    # but the old actor lookup happened *outside* that rescue, so it propagated
    # and turned a successful save into a 500. 38 models pass `actor:`, and every
    # one with an `updated:` event was affected (Tv::Video, Tv::Channel,
    # Marketplace::Deal, Marketplace::Store, Takeaway::MenuItem,
    # Takeaway::Restaurant, Dating::Profile, …).
    #
    # Analytics must never be the reason a write fails, so this degrades to a nil
    # actor instead of raising — matching record_activity!'s existing contract.
    def resolved_activity_actor(name)
      return activity_actor if name.nil?

      if self.class.reflect_on_association(name)&.belongs_to?
        strict_safe(name)
      else
        # A plain method such as Marketplace::Deal#listing_owner.
        public_send(name)
      end
    rescue StandardError => e
      Rails.logger.warn("activity actor skipped: #{e.class}: #{e.message}") if defined?(Rails)
      nil
    end

    def activity_actor
      own = if self.class.reflect_on_association(:user)&.belongs_to?
              strict_safe(:user)
      elsif respond_to?(:user)
              user
      end
      return own if own.present?

      Current.user if defined?(Current) && Current.respond_to?(:user)
    end
  end
end
