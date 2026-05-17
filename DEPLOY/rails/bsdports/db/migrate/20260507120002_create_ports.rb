class CreatePorts < ActiveRecord::Migration[8.1]
  def change
    create_table :ports do |t|
      t.string :name
      t.string :version
      t.references :category, foreign_key: true
      t.string :maintainer
      t.text :comment
      t.text :description
      t.string :homepage
      t.string :pkgpath
      t.boolean :permit_file_distfiles, default: false
      t.date :last_updated
      t.timestamps
    end
    add_index :ports, :name, unique: true
    add_index :ports, :pkgpath, unique: true
  end
end
