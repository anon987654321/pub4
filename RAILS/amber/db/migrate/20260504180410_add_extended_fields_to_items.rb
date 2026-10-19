# frozen_string_literal: true

class AddExtendedFieldsToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :mood_effect, :string
    add_column :items, :life_phase, :string
    add_column :items, :occasion_tags, :string
    add_column :items, :season, :string
  end
end
