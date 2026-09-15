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

    # The results half of live_search_index on its own, so a page can put the
    # field in one place and the results in another — the storefront header
    # holds the field, and the grid sits under a teaser row the form knows
    # nothing about.
    #
    # target is the id finish_live_search streams into. It has to be unique on
    # the page: brgen's search palette renders a #live_search_results of its own
    # ahead of <main> on every surface, and a stream finds the first id in the
    # document. suggestions names the slot for the no-match terms the same way.
    def live_search_results(frame_id:, results_partial:, label:, target: "live_search_results", suggestions: nil)
      slot = suggestions ? tag.div(id: suggestions) : "".html_safe
      frame = turbo_frame_tag(frame_id, data: { turbo_action: "replace" }) do
        tag.div(render(results_partial), id: target, role: "region", aria: { label: "#{label} results" })
      end
      slot + frame
    end
  end
end
