# frozen_string_literal: true

class AddNeighborhoodToDatingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_reference :dating_profiles, :neighborhood, foreign_key: true, index: true
    add_column :dating_profiles, :bydel, :string
  end
end
