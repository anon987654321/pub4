class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.string :title
      t.string :slug
      t.references :blog, foreign_key: true
      t.references :user, foreign_key: true
      t.boolean :published, default: false
      t.datetime :published_at
      t.integer :views_count, default: 0
      t.integer :comments_count, default: 0
      t.timestamps
    end
    add_index :posts, :slug, unique: true
  end
end
