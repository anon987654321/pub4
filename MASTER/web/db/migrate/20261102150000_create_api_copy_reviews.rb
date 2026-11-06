# frozen_string_literal: true

class CreateApiCopyReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :api_copy_reviews do |t|
      t.references :api_key, null: false, foreign_key: true
      t.string :request_id, null: false
      t.string :status, null: false
      t.integer :report_version, null: false
      t.string :creative_sha256, null: false
      t.string :product_sha256
      t.string :reviewer_sha256, null: false
      t.string :source_trust, null: false, default: "caller_supplied_unverified"
      t.json :summary, null: false, default: {}
      t.json :finding_codes, null: false, default: []
      t.timestamps
    end

    add_index :api_copy_reviews, :request_id, unique: true
    add_index :api_copy_reviews, %i[api_key_id created_at]
  end
end
