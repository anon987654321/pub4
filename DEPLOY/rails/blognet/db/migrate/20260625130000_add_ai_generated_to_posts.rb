# frozen_string_literal: true

class AddAiGeneratedToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :ai_generated, :boolean, default: false, null: false
  end
end