# frozen_string_literal: true

class CreateEmailSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :email_subscriptions do |t|
      t.string  :email, null: false
      t.string  :city
      t.string  :locale
      t.string  :token,      null: false
      t.boolean :confirmed,  default: false, null: false
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :email_subscriptions, :email, unique: true
    add_index :email_subscriptions, :token, unique: true
  end
end
