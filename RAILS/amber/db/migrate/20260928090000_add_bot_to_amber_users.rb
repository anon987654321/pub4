# frozen_string_literal: true

class AddBotToAmberUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :bot, :boolean, null: false, default: false
    add_index :users, :bot
  end
end
