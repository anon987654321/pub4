# frozen_string_literal: true

class CreateCrossReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :cross_references do |t|
      t.references :verse,        null: false, foreign_key: true
      t.references :target_verse, null: false, foreign_key: { to_table: :verses }
      t.string     :kind          # lexical | thematic | parallel | typological | fulfillment
      t.text       :note
      t.timestamps
    end
    add_index :cross_references, %i[verse_id target_verse_id], unique: true
  end
end
