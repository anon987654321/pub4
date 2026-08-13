# frozen_string_literal: true

# A mod queue that can resolve a report but cannot stop the person who filed
# the reason for it is half a tool. Moderators could mark a report resolved,
# which takes the content down, and the same account could post the same thing
# again a minute later.
#
# Its own table rather than a flag on community_memberships, because a public
# community takes posts from anyone: the person to ban usually has no
# membership row, and creating one to hold the ban would also make them a
# member and bump members_count.
class CreateCommunityBans < ActiveRecord::Migration[8.1]
  def change
    create_table :community_bans do |t|
      t.references :community, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :banned_by, null: false, foreign_key: { to_table: :users }
      t.string :reason
      # nil is permanent. A temporary ban is the more useful default in
      # practice, so the column exists rather than being bolted on later once
      # every ban in the table is already forever.
      t.datetime :expires_at
      t.timestamps
    end

    add_index :community_bans, %i[community_id user_id], unique: true
    # The question every posting check asks: is this person banned here, now.
    add_index :community_bans, %i[user_id expires_at]
  end
end
