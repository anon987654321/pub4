# frozen_string_literal: true

# Public questions on a listing, answered by whoever is selling it.
#
# The alternative is what the tree had: every buyer asks the same thing in a
# private offer message, the seller answers it five times, and the sixth buyer
# leaves rather than ask. A question is worth more to the people who never asked
# it than to the one who did, which is why the answer is on the listing.
class CreateMarketplaceQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_questions do |t|
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.references :user, null: false, foreign_key: true
      t.references :answered_by, null: true, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.text :answer
      t.datetime :answered_at
      t.timestamps
    end

    # The listing page reads them newest-first and the seller's queue reads the
    # unanswered ones.
    add_index :marketplace_questions, %i[listing_id answered_at]
  end
end
