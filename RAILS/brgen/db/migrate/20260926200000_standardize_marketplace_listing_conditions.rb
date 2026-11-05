# frozen_string_literal: true

class StandardizeMarketplaceListingConditions < ActiveRecord::Migration[8.1]
  def up
    {
      "new" => "new_with_tags",
      "like_new" => "very_good",
      "fair" => "good",
      "poor" => "satisfactory"
    }.each do |from, to|
      execute <<~SQL
        UPDATE marketplace_listings
        SET condition = #{connection.quote(to)}
        WHERE condition = #{connection.quote(from)}
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "marketplace condition mapping is intentionally one-way"
  end
end
