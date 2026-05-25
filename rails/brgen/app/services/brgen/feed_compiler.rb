# frozen_string_literal: true

module Brgen
  class FeedCompiler
    def self.compile(user:, limit: 50)
      ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT item_type, item_id FROM (
            SELECT 'Post' as item_type, id as item_id, created_at, 2 as weight FROM posts
            UNION ALL
            SELECT 'MarketplaceItem' as item_type, id as item_id, created_at, 3 as weight
            FROM brgen_marketplace_items
          ) ORDER BY (weight * 10) + strftime('%s', created_at) DESC LIMIT ?", limit
        ])
      ).to_a
    end
  end
end
