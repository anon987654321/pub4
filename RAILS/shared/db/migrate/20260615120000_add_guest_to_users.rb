# frozen_string_literal: true

class AddGuestToUsers < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:users, :guest)

    add_column :users, :guest, :boolean, default: false, null: false
  end
end
