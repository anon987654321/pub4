# frozen_string_literal: true

class CreateMaintainers < ActiveRecord::Migration[8.1]
  def change
    create_table :maintainers do |t|
      t.string :name, null: false
      t.string :email
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :maintainers, :name, unique: true
  end
end
