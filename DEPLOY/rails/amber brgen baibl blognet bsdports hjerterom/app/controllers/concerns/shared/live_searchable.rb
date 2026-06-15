# frozen_string_literal: true

module Shared
  module LiveSearchable
    extend ActiveSupport::Concern

    included do
      helper_method :live_search_query, :search_meta if respond_to?(:helper_method)
    end

    private

    def live_search_query
      params[:q].to_s.strip
    end

    def search_meta
      @search_meta || {}
    end

    def apply_live_search(scope, columns:, vertical: nil, filters: {})
      query = live_search_query
      return scope if query.empty?

      result = Shared::LiveSearch.search(
        scope,
        query: query,
        columns: columns,
        vertical: vertical,
        filters: filters,
        actor: current_search_actor,
        locality: current_search_locality,
        app: search_app_name
      )
      @search_meta = {
        result_count: result.result_count,
        latency_ms: result.latency_ms,
        suggestions: result.suggestions,
        query: query,
      }
      result.scope
    end

    def live_search_scope(scope, columns:)
      apply_live_search(scope, columns: columns)
    end

    def render_live_search(collection:, partial:, locals: {})
      respond_to do |format|
        format.html
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "live_search_results",
            partial: partial,
            locals: locals.merge(collection: collection, query: live_search_query, search_meta: search_meta)
          )
        end
      end
    end

    def current_search_actor
      return Current.user if defined?(Current) && Current.respond_to?(:user) && Current.user

      current_user if respond_to?(:current_user, true) && current_user
    rescue StandardError
      nil
    end

    def current_search_locality
      return Current.city if defined?(Current) && Current.respond_to?(:city) && Current.city.present?

      params[:city].presence
    rescue StandardError
      nil
    end

    def search_app_name
      Rails.application.class.module_parent_name.underscore
    rescue StandardError
      "unknown"
    end
  end
end