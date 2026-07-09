# frozen_string_literal: true

class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :title, null: false
      t.references :case, null: false, foreign_key: true

      t.timestamps
    end
  end
end