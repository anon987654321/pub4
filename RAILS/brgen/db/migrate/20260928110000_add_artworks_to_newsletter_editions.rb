# frozen_string_literal: true

class AddArtworksToNewsletterEditions < ActiveRecord::Migration[8.1]
  def change
    add_column :newsletter_editions, :artworks, :json, default: []
  end
end
