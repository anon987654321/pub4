# frozen_string_literal: true

class AddMarketplaceListingToConversations < ActiveRecord::Migration[8.1]
  def change
    add_reference :conversations, :marketplace_listing, foreign_key: { to_table: :marketplace_listings }, index: true
  end
end