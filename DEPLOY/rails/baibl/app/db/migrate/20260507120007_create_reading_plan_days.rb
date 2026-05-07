class CreateReadingPlanDays < ActiveRecord::Migration[8.1]
  def change
    create_table :reading_plan_days do |t|
      t.references :reading_plan, foreign_key: true
      t.integer :day_number
      t.references :book, foreign_key: true
      t.integer :chapter_start
      t.integer :chapter_end
      t.datetime :completed_at
      t.timestamps
    end
  end
end
