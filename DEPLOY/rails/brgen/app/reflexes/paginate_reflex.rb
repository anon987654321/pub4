# frozen_string_literal: true

# Infinite scroll — insert_adjacent_html before sentinel div.
# Trigger: data-reflex="scroll->Paginate#load_more" data-page="<%= @page + 1 %>"
class PaginateReflex < ApplicationReflex
  def load_more
    page = element.dataset["page"].to_i
    records = paginate_resource(page)
    morph :nothing
    cable_ready
      .insert_adjacent_html(
        selector: "#paginate-sentinel",
        position: "beforebegin",
        html: render_records(records)
      )
      .broadcast
  end

  private

  def paginate_resource(page)
    resource_class.page(page).per(25)
  end

  def resource_class
    element.dataset["resource"].constantize
  end

  def render_records(records)
    records.map { |r| render(partial: partial_path, locals: { r.model_name.singular.to_sym => r }) }.join
  end

  def partial_path
    element.dataset["partial"] || "#{resource_class.model_name.plural}/#{resource_class.model_name.singular}"
  end
end
