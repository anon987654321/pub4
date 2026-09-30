# frozen_string_literal: true

module Marketplace
  class SearchRanker
    # Request-time relevance is deliberately separate from the persisted listing
    # quality prior. This keeps a global score stable while the same catalogue can
    # answer many different queries without stale query-specific state.
    def initialize(scope, query:, viewer: nil)
      @scope = scope
      @query = query.to_s.strip
      @viewer = viewer
    end

    def relation
      relation = @scope.left_joins(:category)
      relevance = relevance_sql
      preference = preference_sql

      relation.reorder(
        Arel.sql(
          "(#{relevance}) DESC, "           "(marketplace_listings.ranking_score * 0.75 + "           "marketplace_listings.seller_score * 0.15 + "           "#{delivery_quality_sql} * 0.10) DESC, "           "(#{preference}) DESC, marketplace_listings.id DESC"
        )
      )
    end

    def reasons(listing)
      tokens = Shared::Commerce.normalize_query(@query)
      reasons = []

      if tokens.any?
        title = listing.title.to_s.downcase
        description = listing.description.to_s.downcase
        category = listing.category&.name.to_s.downcase

        if tokens.all? { |token| title.include?(token) }
          reasons << I18n.t("marketplace.ranking_reasons.title_match")
        elsif tokens.any? { |token| title.include?(token) }
          reasons << I18n.t("marketplace.ranking_reasons.title_partial")
        elsif tokens.any? { |token| description.include?(token) }
          reasons << I18n.t("marketplace.ranking_reasons.description_match")
        elsif tokens.any? { |token| category.include?(token) }
          reasons << I18n.t("marketplace.ranking_reasons.category_match")
        end
      end

      reasons << I18n.t("marketplace.ranking_reasons.preferred_category") if preferred_category_ids.include?(listing.category_id)
      reasons << I18n.t("marketplace.ranking_reasons.fast_delivery") if listing.delivery_promise.to_i <= 1
      reasons << I18n.t("marketplace.ranking_reasons.trusted_seller") if listing.seller_score.to_f >= 0.85
      reasons << I18n.t("marketplace.ranking_reasons.quality_signal") if listing.ranking_score.to_f >= 0.65

      reasons.first(3)
    end

    private

    attr_reader :scope, :query, :viewer

    def tokens
      @tokens ||= Shared::Commerce.normalize_query(query)
    end

    def connection
      scope.klass.connection
    end

    def relevance_sql
      return "0.0" if tokens.empty?

      clauses = tokens.map do |token|
        quoted = connection.quote("%#{token}%")
        [
          "CASE WHEN LOWER(marketplace_listings.title) LIKE LOWER(#{quoted}) THEN 0.70 ELSE 0 END",
          "CASE WHEN LOWER(marketplace_listings.description) LIKE LOWER(#{quoted}) THEN 0.20 ELSE 0 END",
          "CASE WHEN LOWER(marketplace_categories.name) LIKE LOWER(#{quoted}) THEN 0.10 ELSE 0 END"
        ].join(" + ")
      end

      "(#{clauses.join(" + ")}) / #{tokens.length.to_f}"
    end

    def preferred_category_ids
      @preferred_category_ids ||= begin
        next [] unless viewer

        viewer.marketplace_favorites
              .joins(:listing)
              .distinct
              .limit(50)
              .pluck("marketplace_listings.category_id")
              .compact
      rescue StandardError
        []
      end
    end

    def preference_sql
      ids = preferred_category_ids
      return "0.0" if ids.empty?

      "CASE WHEN marketplace_listings.category_id IN (#{ids.join(",")}) THEN 1.0 ELSE 0.0 END"
    end

    def delivery_quality_sql
      <<~SQL.squish
        CASE marketplace_listings.delivery_promise
          WHEN 0 THEN 1.0
          WHEN 1 THEN 0.9
          WHEN 2 THEN 0.75
          WHEN 3 THEN 0.55
          WHEN 4 THEN 0.3
          ELSE 0.15
        END
      SQL
    end
  end
end
