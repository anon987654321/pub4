# frozen_string_literal: true

class CreateNewsletterEditions < ActiveRecord::Migration[8.1]
  def change
    create_table :newsletter_editions do |t|
      t.string :kind, null: false
      t.string :city
      t.string :app_name, null: false, default: "Brgen"
      t.date :edition_date, null: false
      t.string :subject, null: false
      t.string :preheader
      t.text :lede, null: false
      t.string :sign_off
      t.string :permission_line
      t.string :hero_url
      t.string :hero_alt
      t.string :hero_caption
      t.string :cta_label
      t.string :cta_url
      t.json :stories, default: []
      t.json :deals, default: []
      t.datetime :sent_at
      t.timestamps
    end

    add_index :newsletter_editions, %i[kind city edition_date], unique: true
  end
end