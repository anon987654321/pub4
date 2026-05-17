class CreateWordStudies < ActiveRecord::Migration[8.1]
  def change
    create_table :word_studies do |t|
      t.references :verse,    null: false, foreign_key: true
      t.integer    :position, null: false   # 0-indexed word position in verse
      t.string     :word,     null: false   # surface form
      t.string     :original                # Hebrew / Greek / Arabic
      t.string     :transliteration
      t.string     :strongs                 # H1234 or G5678
      t.string     :language                # hebrew | greek | arabic
      t.text       :definition
      t.timestamps
    end
    add_index :word_studies, %i[verse_id position], unique: true
  end
end
