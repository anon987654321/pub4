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

        notif_klass = if defined?(::Notification)
                        ::Notification
                      elsif defined?(Shared::Notification)
                        Shared::Notification
                      else
                        return
                      end

        # Brgen-style custom (title/body/source) or generic
        if title.present? || body.present? || (source && notif_klass.column_names.include?("source_type") rescue false)
          attrs = {
            title: title,
            body: body,
            source_type: source&.class&.name,
            source_id: source&.id,
          }.merge(extra).compact
          if recipient.respond_to?(:notifications)
            recipient.notifications.create!(attrs)
          else
            notif_klass.create!(attrs.merge(user: recipient).compact)
          end
        else
          # Structured social notification
          attrs = { actor: actor, kind: kind, notifiable: source }.merge(extra).compact
          if recipient.respond_to?(:notifications)
            recipient.notifications.create!(attrs)
          else
            notif_klass.create!(attrs.merge(user: recipient).compact)
          end
        end
      rescue StandardError => e
        # KISS: never let notification side-effect crash the main flow
        Rails.logger&.warn("Notification delivery skipped: #{e.class}: #{e.message}") if defined?(Rails)
      end
    end

    # Instance convenience (for models that include this)
    def deliver_notification(recipient, **kwargs)
      self.class.deliver_notification(recipient, **kwargs)
    end
  end
end
