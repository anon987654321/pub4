# frozen_string_literal: true

# The subscribe loop: a user joins communities (r/<city>-style) and gets a feed
# built from them. Distinct from Follow (user->user); this is user->community.
class CreateCommunityMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :community_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :community, null: false, foreign_key: true
      t.timestamps
    end
    add_index :community_memberships, %i[user_id community_id], unique: true
  end
end
