# frozen_string_literal: true

class AlignNotificationsSchema < ActiveRecord::Migration[8.1]
  def up
    change_table :notifications, bulk: true do |t|
      t.references :actor, foreign_key: { to_table: :users }, null: true unless column_exists?(:notifications, :actor_id)
      t.string :kind, null: false, default: "custom" unless column_exists?(:notifications, :kind)
      t.string :notifiable_type unless column_exists?(:notifications, :notifiable_type)
      t.integer :notifiable_id unless column_exists?(:notifications, :notifiable_id)
    end

    change_column_null :notifications, :title, true if column_exists?(:notifications, :title)

    add_index :notifications, %i[notifiable_type notifiable_id], if_not_exists: true

    execute <<~SQL.squish if column_exists?(:notifications, :source_type)
      UPDATE notifications
      SET notifiable_type = source_type, notifiable_id = source_id
      WHERE source_type IS NOT NULL AND notifiable_type IS NULL
    SQL
  end

  def down
    remove_index :notifications, %i[notifiable_type notifiable_id], if_exists: true
    change_column_null :notifications, :title, false if column_exists?(:notifications, :title)

    change_table :notifications, bulk: true do |t|
      t.remove_references :actor, foreign_key: true if column_exists?(:notifications, :actor_id)
      t.remove :kind if column_exists?(:notifications, :kind)
      t.remove :notifiable_type if column_exists?(:notifications, :notifiable_type)
      t.remove :notifiable_id if column_exists?(:notifications, :notifiable_id)
    end
  end
end