# frozen_string_literal: true

module Shared
  module SearchHelper
    def live_search_index(url:, results_partial:, placeholder: "Search…", label: "Search", frame_id: nil, query: nil,
**locals, &block)
      render(
        partial: "shared/live_search_index",
        locals: {
          url:,
          results_partial:,
          placeholder:,
          label:,
          frame_id: frame_id || "#{controller_name.dasherize}-index",
          query:,
          filter_fields_proc: (block if block_given?),
          **locals,
        },
      )
    end

    def live_search_form(url:, placeholder: "Search…", label: "Search", query: nil, turbo_frame: "live_search_results",
**locals, &block)
      render(
        partial: "shared/live_search_form",
        locals: {
          url:,
          placeholder:,
          label:,
          query: query || params[:q],
          turbo_frame:,
          filter_fields_proc: (block if block_given?),
          **locals,
        },
      )
    end
  end
end
