# frozen_string_literal: true

class AddNeighborhoodToDatingProfiles < ActiveRecord::Migration[8.1]
  def change
    # The key this reference lacks is 20260914120000's: this migration has run on
    # vm23, so an edit here changes no database.
    add_reference :dating_profiles, :neighborhood, index: true, if_not_exists: true # scan: intentional
    add_column :dating_profiles, :bydel, :string
  end
end
