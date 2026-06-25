# frozen_string_literal: true

module Shared
  class PaginateReflex < Shared::ApplicationReflex
    def load_more
      page = element.dataset["page"].to_i
      records = paginate_resource(page)
      morph :nothing
      cable_ready
        .insert_adjacent_html(
          selector: element.dataset["selector"].presence || "#paginate-sentinel",
          position: "beforebegin",
          html: render_records(records)
        )
        .broadcast
    end

    private

    def paginate_resource(page)
      resource_class.page(page).per(per_page)
    end

    def resource_class
      element.dataset["resource"].constantize
    end

    def per_page
      element.dataset["per-page"].presence&.to_i || 25
    end

    def render_records(records)
      records.map { |record| render(partial: partial_path, locals: partial_locals(record)) }.join
    end

    def partial_path
      element.dataset["partial"] || "#{resource_class.model_name.plural}/#{resource_class.model_name.singular}"
    end

    def partial_locals(record)
      { record.model_name.singular.to_sym => record }
    end
  end
end