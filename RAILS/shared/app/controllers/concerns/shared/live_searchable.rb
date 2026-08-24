# frozen_string_literal: true

module Shared
  module LiveSearchable
    extend ActiveSupport::Concern

    included do
      helper_method :live_search_query, :search_suggestions if respond_to?(:helper_method)
    end

    private

    def live_search_query
      params[:q].to_s.strip
    end

    def search_suggestions
      @search_suggestions || []
    end

    def live_search_scope(scope, columns:)
      apply_live_search(scope, columns:)
    end

    def apply_live_search(scope, columns:, vertical: nil, filters: {})
      filters.each do |key, value|
        scope = scope.where(key => value) if value.present?
      end
      return scope if live_search_query.blank?

      @live_search_result = Shared::LiveSearch.search(
        scope,
        query: live_search_query,
        columns:,
        vertical:,
        app: live_search_app_name,
      )
      @search_suggestions = @live_search_result.suggestions
      @live_search_result.scope
    end

    def live_search_app_name
      Rails.application.class.module_parent_name.to_s.downcase
    end

    def finish_live_search(partial:, locals: {})
      respond_to do |format|
        format.html
        format.turbo_stream do
          streams = []
          streams << turbo_stream.replace(
            "search_suggestions",
            partial: "shared/search_suggestions",
            locals: { suggestions: search_suggestions },
          )
          streams << turbo_stream.replace(
            "live_search_results",
            partial:,
            locals:,
          )
          render turbo_stream: streams
        end
      end
    end
  end
end
