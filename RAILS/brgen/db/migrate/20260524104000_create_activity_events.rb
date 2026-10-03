# frozen_string_literal: true

class CreateActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_events do |t|
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :locality
      t.string :visibility, null: false, default: 'public'
      t.string :moderation_state, null: false, default: 'clean'
      t.string :source_vertical, null: false
      t.string :event_name, null: false
      t.string :object_type, null: false
      t.integer :object_id, null: false
      t.json :metadata
      t.timestamps
    end

    add_index :activity_events, %i[source_vertical created_at]
    add_index :activity_events, %i[object_type object_id]
    add_index :activity_events, %i[locality created_at]
  end
end
