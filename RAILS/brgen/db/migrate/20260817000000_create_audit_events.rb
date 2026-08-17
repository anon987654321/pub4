# frozen_string_literal: true

# The record of privileged actions, which until now had none.
#
# Bans, unbans and moderator appointments all wrote their outcome onto a row and
# nothing else: lifting a ban destroyed the only evidence that it had ever
# existed, along with who imposed it and why. See Shared::AuditEvent for the
# longer version and for why activity events are not this.
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.string :action, null: false
      # Nullable, and no cascade: a system action has no actor, and a deleted
      # account must not take the record of what it did with it. Shared::AuditEvent
      # renders a placeholder for that case rather than an empty cell.
      t.references :actor, foreign_key: { to_table: :users }

      # Plain columns, not a polymorphic association. The record an audit event
      # names is routinely destroyed — that is the case this table exists for.
      t.string :target_type
      t.integer :target_id

      # What the action was scoped to (a Community), so a moderator team can read
      # its own log without being handed every other community's.
      t.string :context_type
      t.integer :context_id

      t.json :metadata, null: false, default: {}
      # Distinct from created_at because a backfilled or queued write should say
      # when the action happened, not when the row landed.
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :audit_events, %i[context_type context_id occurred_at]
    add_index :audit_events, %i[action occurred_at]
    add_index :audit_events, %i[target_type target_id]
  end
end
