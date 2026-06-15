# frozen_string_literal: true

module Shared
  module LiveSearchable
    extend ActiveSupport::Concern

    included do
      helper_method :live_search_query if respond_to?(:helper_method)
    end

    private

    def live_search_query
      params[:q].to_s.strip
    end

    def live_search_scope(scope, columns:)
      query = live_search_query
      return scope if query.empty?

      adapter = ActiveRecord::Base.connection.adapter_name.downcase
      if adapter.include?("sqlite")
        like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        predicate = columns.map { |column| "#{column} LIKE :query" }.join(" OR ")
        scope.where(predicate, query: like)
      else
        like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        predicate = columns.map { |column| "#{column} ILIKE :query" }.join(" OR ")
        scope.where(predicate, query: like)
      end
    end

    def render_live_search(collection:, partial:, locals: {})
      respond_to do |format|
        format.html
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "live_search_results",
            partial: partial,
            locals: locals.merge(collection: collection, query: live_search_query)
          )
        end
      end
    end
  end
end
