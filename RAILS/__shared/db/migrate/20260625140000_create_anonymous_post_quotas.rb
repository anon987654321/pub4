# frozen_string_literal: true

class CreateAnonymousPostQuotas < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:anonymous_post_quotas)

    create_table :anonymous_post_quotas do |t|
      t.string :fingerprint, null: false
      t.integer :post_count, null: false, default: 0
      t.timestamps
    end

    add_index :anonymous_post_quotas, :fingerprint, unique: true
  end
end
