class CreateBlogs < ActiveRecord::Migration[8.1]
  def change
    create_table :blogs do |t|
      t.string :name
      t.text :description
      t.string :slug
      t.references :user, foreign_key: true
      t.boolean :published, default: false
      t.integer :posts_count, default: 0
      t.timestamps
    end
    add_index :blogs, :slug, unique: true
  end
end
