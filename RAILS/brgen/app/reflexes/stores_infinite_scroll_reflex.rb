# frozen_string_literal: true

class StoresInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "marketplace/stores/card", as: :store

  private

  def scope
    scope = Marketplace::Store.active.recent
    scope = scope.by_vertical(element.dataset["vertical"]) if element.dataset["vertical"].present?
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("name LIKE ? OR description LIKE ? OR vertical LIKE ?", term, term, term)
  end
end
