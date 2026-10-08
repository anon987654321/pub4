# frozen_string_literal: true

class CreateTvSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :tv_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tv_channel, null: false, foreign_key: true
      t.boolean :notify_on_upload

      t.timestamps
    end
  end
end
