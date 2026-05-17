class CreateReadingPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :reading_plans do |t|
      t.string :name
      t.text :description
      t.integer :duration_days
      t.references :user, foreign_key: true
      t.timestamps
    end
  end
end
