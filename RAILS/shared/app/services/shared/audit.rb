# frozen_string_literal: true

module Shared
  # The one way an audit record is written.
  #
  # A service rather than a concern, because the operations worth auditing are
  # not model lifecycle events. Lifting a ban is a destroy, appointing a
  # moderator is an `update!(role:)` on a membership that updates for a dozen
  # other reasons, and neither carries the acting moderator — `Current.user` is
  # brgen-local and this file is loaded by three apps, so reaching for it here
  # would NameError in the other two. The caller knows who acted; it passes them.
  class Audit
    # Actions are dotted and hierarchical (`community.ban.created`) so the
    # summary i18n key is derivable and a future filter can match a prefix.
    def self.record!(action:, actor: nil, target: nil, context: nil, metadata: {})
      return false unless available?

      AuditEvent.create!(
        action: action.to_s,
        actor:,
        target_type: target&.class&.name,
        target_id: target&.id,
        context_type: context&.class&.name,
        context_id: context&.id,
        metadata:,
        occurred_at: Time.current,
      )
      true
    rescue StandardError => e
      # An audit write must never be the reason a moderator's action fails —
      # same contract as Shared::DomainEvent, and for the stronger reason: a ban
      # that could not be recorded is still a ban that should take effect. The
      # log is loud so a silently unaudited action is findable afterwards.
      Rails.logger.error("audit write failed for #{action}: #{e.class}: #{e.message}") if defined?(Rails)
      false
    end

    # bsdports has no moderation surface and so no audit_events table. Asking the
    # connection is the honest check; `defined?` would be true in all three apps
    # because the model ships in the shared engine regardless.
    def self.available?
      AuditEvent.table_exists?
    rescue StandardError
      false
    end
  end
end
