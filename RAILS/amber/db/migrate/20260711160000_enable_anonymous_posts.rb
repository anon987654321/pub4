# frozen_string_literal: true

class EnableAnonymousPosts < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:users, :guest)
      add_column :users, :guest, :boolean, default: false, null: false
    end

    unless column_exists?(:posts, :anonymous)
      add_column :posts, :anonymous, :boolean, default: false, null: false
    end

    change_column_null :posts, :outfit_id, true
    change_column_null :posts, :item_id, true

    return if table_exists?(:anonymous_post_quotas)

    create_table :anonymous_post_quotas do |t|
      t.string :fingerprint, null: false
      t.integer :post_count, null: false, default: 0
      t.timestamps
    end

    add_index :anonymous_post_quotas, :fingerprint, unique: true
  end
end
