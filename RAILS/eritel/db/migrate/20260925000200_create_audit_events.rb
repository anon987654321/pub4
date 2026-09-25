class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :domain, foreign_key: true
      t.string :event_type, null: false
      t.string :actor, null: false
      t.text :data, null: false, default: "{}"
      t.timestamps
    end

    add_index :audit_events, :event_type
    add_index :audit_events, :created_at
  end
end
