# frozen_string_literal: true

# A community's own reference pages, with the history that makes a bad edit
# recoverable. Moderators write; whoever can read the community reads it.
class CreateCommunityWiki < ActiveRecord::Migration[8.1]
  def change
    create_table :community_wiki_pages do |t|
      t.references :community, null: false, foreign_key: true
      t.references :updated_by, null: true, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.string :slug, null: false
      t.text :body, null: false
      t.timestamps
    end

    # One page per name per community, and the slug is how it is addressed.
    add_index :community_wiki_pages, %i[community_id slug], unique: true

    # Every save keeps the body it replaced. A revert writes a new revision from
    # an old body rather than deleting the ones after it: a wiki whose history
    # can be edited is a wiki nobody can audit.
    create_table :community_wiki_revisions do |t|
      t.references :page, null: false, foreign_key: { to_table: :community_wiki_pages }
      t.references :user, null: true, foreign_key: true
      t.text :body, null: false
      t.datetime :created_at, null: false
    end

    add_index :community_wiki_revisions, %i[page_id created_at]
  end
end
