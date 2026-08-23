# frozen_string_literal: true

# DRY + KISS for notification delivery across models/controllers.
# Handles both brgen's Notification (title/body/source) and Shared::Notification (kind/notifiable)
# and falls back safely. Prefers association when available.
module Shared
  module Notifiable
    extend ActiveSupport::Concern

    class_methods do
      # Deliver a notification to a recipient (User or anything with #notifications or id).
      # For custom order-style: pass title:/body:/source:
      # For social: pass actor:/kind:/source: (source becomes notifiable)
      def deliver_notification(recipient, title: nil, body: nil, source: nil, actor: nil, kind: "custom", **extra)
        return unless recipient

        notif_klass = notification_class or return

        attrs = if title_body_shape?(notif_klass, title:, body:, source:)
                  custom_attrs(notif_klass, title:, body:, source:, kind:, **extra)
        else
                  { actor:, kind:, notifiable: source }.merge(extra).compact
        end

        write_notification(notif_klass, recipient, attrs)
      rescue StandardError => e
        # KISS: never let notification side-effect crash the main flow
        Rails.logger&.warn("Notification delivery skipped: #{e.class}: #{e.message}") if defined?(Rails)
      end

      # brgen names it at the top level; the other two apps take the engine's.
      def notification_class
        return ::Notification if defined?(::Notification)

        Shared::Notification if defined?(Shared::Notification)
      end

      # brgen's title/body/source row, as opposed to the social actor/notifiable
      # one. The rescue covers a model whose table is not there to ask.
      def title_body_shape?(notif_klass, title:, body:, source:)
        return true if title.present? || body.present?

        source.present? && notif_klass.column_names.include?("source_type")
      rescue StandardError
        false
      end

      def custom_attrs(notif_klass, title:, body:, source:, kind:, **extra)
        attrs = {
          title:,
          body:,
          source_type: source&.class&.name,
          source_id: source&.id,
        }.merge(extra).compact

        # kind was dropped on this branch, so every title/body notification — an
        # order advancing, a saved search matching, a listing about to lapse —
        # was written with the column default "custom". brgen pushes on kind, and
        # "custom" is not in PUSHABLE_KINDS, so none of them ever reached a lock
        # screen however urgent they were.
        #
        # Guarded on the column because the other apps' notification model is a
        # different shape and passing an attribute it lacks would raise inside a
        # rescue that swallows it.
        attrs[:kind] = kind if kind.present? && notif_klass.column_names.include?("kind")
        attrs
      end

      # Through the association when the recipient has one, so scoping and
      # counter caches apply; otherwise by foreign key.
      def write_notification(notif_klass, recipient, attrs)
        if recipient.respond_to?(:notifications)
          recipient.notifications.create!(attrs)
        else
          notif_klass.create!(attrs.merge(user: recipient).compact)
        end
      end
    end

    # Instance convenience (for models that include this)
    def deliver_notification(recipient, **kwargs)
      self.class.deliver_notification(recipient, **kwargs)
    end
  end
end
