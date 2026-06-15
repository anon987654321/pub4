# frozen_string_literal: true

class SearchController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: :index

  def index
    @query = live_search_query
    payload = Brgen::GlobalSearch.call(
      query: @query,
      actor: current_search_actor,
      locality: current_search_locality
    )
    @results = payload[:results]
    @groups = payload[:groups]
    @search_meta = {
      result_count: payload[:result_count],
      latency_ms: payload[:latency_ms],
      suggestions: payload[:suggestions],
      query: @query,
    }

    respond_to do |format|
      format.html
      format.json do
        render json: {
          query: @query,
          count: payload[:result_count],
          results: @results.map { |r| { type: r.type, id: r.id, title: r.title, subtitle: r.subtitle, url: r.url } },
          suggestions: payload[:suggestions],
        }
      end
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "live_search_results",
          partial: "search/results",
          locals: { results: @results, groups: @groups, query: @query, search_meta: @search_meta }
        )
      end
    end
  end
end