# frozen_string_literal: true

module Shared
  module SearchHelper
    def live_search_form(url:, placeholder: "Search…", label: "Search", query: nil, turbo_frame: "live_search_results", **locals, &block)
      render(
        partial: "shared/live_search_form",
        locals: {
          url: url,
          placeholder: placeholder,
          label: label,
          query: query || params[:q],
          turbo_frame: turbo_frame,
          **locals
        },
        &block
      )
    end
  end
end