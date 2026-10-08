# frozen_string_literal: true

# dating_profiles.neighborhood_id was added without a foreign key, so a profile
# could name a neighborhood that no longer exists and render a blank where its
# bydel belongs. Rows pointing at a missing neighborhood are orphans already;
# they lose the reference before the constraint goes on, or the table rebuild
# SQLite needs for add_foreign_key would refuse them.
#
# on_delete: :nullify, because the profile's belongs_to is optional and nothing
# on Neighborhood owns profiles: removing a neighborhood leaves the profile
# standing without one, as it stands today when the column is empty.
class DatingProfilesNeighborhoodForeignKey < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      UPDATE dating_profiles
         SET neighborhood_id = NULL
       WHERE neighborhood_id IS NOT NULL
         AND neighborhood_id NOT IN (SELECT id FROM neighborhoods)
    SQL
    return if foreign_key_exists?(:dating_profiles, :neighborhoods)

    add_foreign_key :dating_profiles, :neighborhoods, on_delete: :nullify
  end

  def down
    return unless foreign_key_exists?(:dating_profiles, :neighborhoods)

    remove_foreign_key :dating_profiles, :neighborhoods
  end
end
