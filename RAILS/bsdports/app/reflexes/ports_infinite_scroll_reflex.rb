# frozen_string_literal: true

class PortsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "ports/row", as: :port

  private

  def scope
    scope = Port.includes(:category)
    if element.dataset["q"].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
      scope = scope.where("name LIKE :q OR comment LIKE :q OR description LIKE :q", q: term)
    end
    scope = scope.by_category(element.dataset["categoryId"]) if element.dataset["categoryId"].present?
    scope.order(element.dataset["sort"] == "updated" ? "last_updated DESC" : :name)
  end
end
