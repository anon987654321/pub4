# frozen_string_literal: true

class CreateBrgenSocialTables < ActiveRecord::Migration[8.0]
  def change
    unless table_exists?(:follows)
      create_table :follows do |t|
        t.references :follower, null: false, foreign_key: { to_table: :users }
        t.references :followed, null: false, foreign_key: { to_table: :users }
        t.timestamps
      end
      add_index :follows, %i[follower_id followed_id], unique: true
    end

    if table_exists?(:reactions) && !column_exists?(:reactions, :reactable_type)
      add_reference :reactions, :reactable, polymorphic: true
      change_column_null :reactions, :post_id, true if column_exists?(:reactions, :post_id)
      change_column_default :reactions, :kind, from: nil, to: "like" if column_exists?(:reactions, :kind)
    end

    if table_exists?(:reactions) && column_exists?(:reactions, :reactable_type)
      add_index :reactions,
                %i[user_id reactable_type reactable_id post_id kind],
                unique: true,
                name: "idx_reactions_unique_user_target_kind",
                if_not_exists: true
    end
  end
end