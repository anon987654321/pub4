class CreateDependencies < ActiveRecord::Migration[8.1]
  def change
    create_table :dependencies do |t|
      t.references :port, foreign_key: true
      t.references :depends_on, foreign_key: { to_table: :ports }
      t.string :dep_type
      t.timestamps
    end
  end
end
