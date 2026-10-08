# frozen_string_literal: true

module Shared
  # What happened *to* the system, as opposed to what happened *in* the product.
  #
  # ActivityEvent is the other one and they are not interchangeable: it carries a
  # `visibility` column, a `moderation_state`, and `for_city_home`, because it is
  # rendered on public surfaces. An audit record is the opposite — it exists to be
  # read by the people who hold the power it records, and putting a ban into a
  # feed would publish exactly the thing a ban is supposed to keep quiet.
  #
  # The trigger for building it: Communities::BansController#destroy is
  # `find(params[:id]).destroy`. CommunityBan carries `banned_by`, `reason` and
  # `expires_at`, so every fact about a ban lived on the row — and lifting one
  # deleted all of it. Who banned whom, why, and who let them back in was
  # unrecoverable a second after the button was pressed, in the one part of the
  # app where "who did this" is the whole question.
  #
  # That is also why target is two plain columns rather than a polymorphic
  # belongs_to. The record an audit event names is frequently *already destroyed*
  # — that is the case it was built for — so an association would be a
  # permanently nil read under strict_loading. ActivityEvent made the same call
  # with ActivityEvent subject_type/subject_id for the same reason.
  class AuditEvent < ApplicationRecord
    self.table_name = "audit_events"

    belongs_to :actor, class_name: "User", optional: true

    validates :action, :occurred_at, presence: true

    scope :recent, -> { order(occurred_at: :desc) }
    scope :for_context, ->(record) {
      where(context_type: record.class.name, context_id: record.id)
    }

    # Append-only from application code. `readonly?` covers update *and* destroy
    # — ActiveRecord::Persistence#destroy raises ReadOnlyRecord before it touches
    # the row — so this is one line instead of two callbacks that a later
    # `update_column` would walk straight past anyway.
    #
    # Retention is a separate lever and deliberately not built yet: deleting old
    # audit rows is an operator decision with a legal shape, not something an
    # after_create should be doing on its own.
    def readonly? = persisted?

    # The actor's name at read time, not at write time. A renamed account should
    # read as its current name in the log — this is a record of an action, not of
    # a display string. `deleted_actor` is the honest answer when the account is
    # gone, rather than a blank cell that reads as "nobody did this".
    def actor_label
      actor&.display_name || I18n.t("audit.deleted_actor")
    end

    # Rendered from the action key, so a new audited operation is one i18n entry
    # in two locales and not a case statement in a view.
    def summary
      I18n.t(
        "audit.#{action}",
        **metadata.to_h.symbolize_keys.merge(actor: actor_label),
        default: action,
      )
    end
  end
end
