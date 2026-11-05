# frozen_string_literal: true

# A dish's photo was looked up by its Norwegian name in a helper map, so
# renaming a dish silently dropped its photo. The row now keeps the path;
# existing dishes are filled from the seed map once.
class AddPhotoPathToMenuItems < ActiveRecord::Migration[8.0]
  def change
    add_column :menu_items, :photo_path, :string

    up_only do
      photos = YAML.load_file(Rails.root.join("db/food_photos.yml"))
      photos.each do |name, path|
        execute(sanitize_sql([ "UPDATE menu_items SET photo_path = ? WHERE name = ?", path, name ]))
      end
    end
  end

  private

  def sanitize_sql(statement)
    ActiveRecord::Base.sanitize_sql_array(statement)
  end
end
