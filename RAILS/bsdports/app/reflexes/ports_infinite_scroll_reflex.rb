# frozen_string_literal: true

class PortsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "ports/row", as: :port

  private

  # The search and order the index ran for page 1, so every page draws from
  # one set in one order.
  def scope
    data = element.dataset
    Port.includes(:category).listed(query: data["q"], category_id: data["categoryId"], sort: data["sort"])
  end
end
