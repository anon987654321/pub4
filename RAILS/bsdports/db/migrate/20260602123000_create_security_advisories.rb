# frozen_string_literal: true

class CreateSecurityAdvisories < ActiveRecord::Migration[8.1]
  def change
    create_table :security_advisories do |t|
      t.references :port, null: true, foreign_key: true
      t.string :identifier
      t.string :title, null: false
      t.text :description
      t.integer :severity, default: 1
      t.float :cvss_score
      t.datetime :published_at
      t.datetime :resolved_at
      t.string :source_url
      t.timestamps
    end

    add_index :security_advisories, :identifier, unique: true
    add_index :security_advisories, :published_at
  end
end
