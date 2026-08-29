# frozen_string_literal: true

# The repost button has been on every feed card since the design landed, with
# no route, model, controller or column behind it. For a while it also carried
# data-controller="action" with no URL, so pressing it added the active class,
# sent nothing, and told the user their repost had landed until the next render
# took it back.
#
# (shared/_action_bar.html.erb carries a second copy of the button, but no view
# in any of the three apps renders that partial — see TODO.md 1.1.)
class CreateReposts < ActiveRecord::Migration[8.1]
  def change
    create_table :reposts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :post, null: false, foreign_key: true
      t.timestamps
    end

    # One repost per user per post. The toggle is create-or-destroy, so without
    # this a double submit leaves two rows and the counter cache counts both.
    add_index :reposts, %i[user_id post_id], unique: true

    # Counter cache: the feed renders a count on every card, and the button is
    # on all 25 of them.
    add_column :posts, :reposts_count, :integer, default: 0, null: false
  end
end
