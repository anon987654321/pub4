class AddUserDescriptionToCommunities < ActiveRecord::Migration[8.1]
  def change
    add_column :communities, :user_id, :integer unless column_exists?(:communities, :user_id)
    add_column :communities, :description, :text unless column_exists?(:communities, :description)
  end
end
