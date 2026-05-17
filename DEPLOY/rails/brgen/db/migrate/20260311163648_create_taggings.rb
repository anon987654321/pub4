class CreateTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :taggings do |t|
      t.references :taggable, polymorphic: true, null: false
      t.references :hashtag, null: false, foreign_key: true

      t.timestamps
    end
  end
end
