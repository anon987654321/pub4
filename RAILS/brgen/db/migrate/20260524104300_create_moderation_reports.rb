# frozen_string_literal: true

class CreateModerationReports < ActiveRecord::Migration[8.1]
  def change
    create_table :moderation_reports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :reportable_type, null: false
      t.integer :reportable_id, null: false
      t.string :reason, null: false
      t.text :details
      t.string :status, null: false, default: 'open'
      t.timestamps
    end

    add_index :moderation_reports, %i[reportable_type reportable_id]
    add_index :moderation_reports, %i[status created_at]
  end
end
